package cn.com.omnimind.bot.codex

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.ai.assistance.operit.terminal.TerminalManager
import com.ai.assistance.operit.terminal.setup.EnvironmentSetupLogic
import cn.com.omnimind.baselib.database.DatabaseHelper
import cn.com.omnimind.bot.BuildConfig
import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import cn.com.omnimind.bot.util.TaskRuntimeSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

private const val CODEX_INTERNAL_MODEL_PROVIDER = "omnimind"

class CodexAppServerManager private constructor(
    private val context: Context
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val sessionMutex = Mutex()
    private val configWriteMutex = Mutex()
    private val sessionStateLock = Any()
    private val serverMessageBarrier = CodexServerMessageBarrier()
    private val sessionGenerationLock = Any()
    private val sessionGenerationPreferences = appContext.getSharedPreferences(
        SESSION_GENERATION_PREFERENCES,
        Context.MODE_PRIVATE,
    )
    private val configMigrationPreferences = appContext.getSharedPreferences(
        CONFIG_MIGRATION_PREFERENCES,
        Context.MODE_PRIVATE,
    )
    private val threadStartMutex = Mutex()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bindingRepository = CodexThreadBindingRepository(appContext)
    private val remoteConfigStore = CodexRemoteBridgeConfigStore(appContext)
    private val activeTurnsByThreadId = ConcurrentHashMap<String, String>()
    private val eventListeners = CodexEventListenerRegistry()
    private val nextEventStreamToken = AtomicLong(0L)
    private val serverRequests = CodexServerRequestRegistry()
    private val serverRequestResponder = CodexServerRequestResponder(serverRequests)
    /** Single-fire guard: threadId -> terminal token (turnId or synthetic). */
    private val finishedNotifyOnceByThread = ConcurrentHashMap<String, String>()

    @Volatile
    private var pendingThreadStartConversationId: Long? = null

    @Volatile
    private var session: CodexAppServerSession? = null
    @Volatile
    private var activeRuntime: CodexRuntimeKind? = null
    @Volatile
    private var activeSessionGeneration: Long = NO_SESSION_GENERATION
    /** Guarded by [sessionStateLock]. Transport-running is not initialized-ready. */
    private var activeSessionReadiness = CodexSessionReadiness.DISCONNECTED

    fun registerEventListener(
        engineToken: String,
        listener: (Map<String, Any?>) -> Unit,
    ): String {
        val streamToken = "$engineToken-stream-${nextEventStreamToken.incrementAndGet()}"
        lateinit var registration: CodexEventListenerRegistration
        // Register first, then capture the exact current-session PENDING set
        // under the same ordering boundary used by request registration,
        // resolution, and generation invalidation. A queued live delivery and
        // this replay converge on the per-stream pending delivery key.
        val pendingReplay = synchronized(sessionStateLock) {
            registration = eventListeners.register(
                engineToken = engineToken,
                streamToken = streamToken,
                listener = listener,
            )
            val currentSession = session
            val currentGeneration = activeSessionGeneration
            if (currentSession?.isRunning == true &&
                currentGeneration != NO_SESSION_GENERATION
            ) {
                serverRequests.snapshotPending(
                    sessionGeneration = currentGeneration,
                    sessionIdentity = currentSession,
                )
            } else {
                emptyList()
            }
        }
        Log.i(
            TAG,
            "event_listener action=registered engineToken=$engineToken " +
                "streamToken=$streamToken listenerCount=${eventListeners.size()} " +
                "pendingReplayCount=${pendingReplay.size}",
        )
        pendingReplay.forEach { request ->
            deliverEventToRegistration(
                registration = registration,
                event = buildCodexPendingServerRequestEvent(
                    request = request,
                    workspaceId = CodexAppServerSession.DEFAULT_WORKSPACE_ID,
                    replayed = true,
                ),
                pendingRequest = request,
                deliveryAction = "event_replayed",
            )
        }
        return streamToken
    }

    fun unregisterEventListener(
        streamToken: String,
        reason: String,
    ) {
        val removed = eventListeners.unregister(streamToken) ?: return
        Log.i(
            TAG,
            "event_listener action=removed engineToken=${removed.engineToken} " +
                "streamToken=${removed.streamToken} reason=$reason " +
                "listenerCount=${eventListeners.size()}",
        )
    }

    suspend fun status(): Map<String, Any?> {
        val runtime = resolveRuntime()
        val (connected, sessionGeneration) = synchronized(sessionStateLock) {
            Pair(
                isCodexSessionReadyForUse(
                    readiness = activeSessionReadiness,
                    transportRunning = session?.isRunning == true,
                    runtimeMatches = activeRuntime == runtime.kind,
                ),
                activeSessionGeneration,
            )
        }
        val probe = when (runtime.kind) {
            CodexRuntimeKind.REMOTE -> probeRemoteCodex(runtime.remoteConfig)
            CodexRuntimeKind.LOCAL -> probeCodex()
        }
        return linkedMapOf(
            "connected" to connected,
            "ready" to probe.ready,
            "version" to probe.version,
            "error" to probe.error,
            "codexHome" to CodexAppServerDefaults.CODEX_HOME,
            "cwd" to resolveDefaultCwd(),
            "runtime" to runtime.kind.payloadValue,
            "remoteEnabled" to runtime.remoteConfig.enabled,
            "remoteBridgeUrl" to runtime.remoteConfig.bridgeUrl,
            "remoteCwd" to runtime.remoteConfig.cwd,
            "remoteConfigured" to runtime.remoteConfig.isConfigured,
            "remoteTransport" to probe.details["appServerTransport"],
            "remoteDesktopAvailable" to probe.details["desktopAppServerAvailable"],
            "remoteActiveConnections" to probe.details["activeConnections"],
            "remoteUptimeMs" to probe.details["uptimeMs"],
            "sessionGeneration" to sessionGeneration,
        )
    }

    suspend fun connect(): Map<String, Any?> {
        sessionMutex.withLock {
            val runtime = resolveRuntime()
            val (existing, canReuse) = synchronized(sessionStateLock) {
                val currentSession = session
                Pair(
                    currentSession,
                    currentSession != null &&
                        isCodexSessionReadyForUse(
                            readiness = activeSessionReadiness,
                            transportRunning = currentSession.isRunning,
                            runtimeMatches = activeRuntime == runtime.kind,
                        ),
                )
            }
            if (canReuse) {
                return status()
            }
            serverMessageBarrier.run {
                synchronized(sessionStateLock) {
                    if (existing != null &&
                        activeSessionGeneration != NO_SESSION_GENERATION
                    ) {
                        invalidateServerRequestsLocked(
                            generation = activeSessionGeneration,
                            sessionIdentity = existing,
                            reason = "session_replaced",
                        )
                    }
                    if (session === existing) {
                        clearActiveSessionLocked()
                    }
                }
            }
            existing?.disconnect()
            activeTurnsByThreadId.clear()
            finishedNotifyOnceByThread.clear()
            val generation = allocateSessionGeneration()
            lateinit var nextSession: CodexAppServerSession
            nextSession = CodexAppServerSession(
                context = appContext,
                scope = scope,
                onServerMessage = { message ->
                    // Capture both values at construction. Never label a delayed
                    // message by reading whichever session happens to be current.
                    handleServerMessage(
                        sourceGeneration = generation,
                        sourceSession = nextSession,
                        message = message,
                    )
                },
                connectionFactory = when (runtime.kind) {
                    CodexRuntimeKind.REMOTE -> {
                        {
                            RemoteCodexBridgeConnection(
                                config = runtime.remoteConfig,
                                scope = scope
                            )
                        }
                    }
                    CodexRuntimeKind.LOCAL -> null
                }
            )
            serverMessageBarrier.run {
                synchronized(sessionStateLock) {
                    session = nextSession
                    activeSessionGeneration = generation
                    activeRuntime = runtime.kind
                    activeSessionReadiness = CodexSessionReadiness.STARTING
                }
            }
            Log.i(
                TAG,
                "session action=starting generation=$generation runtime=${runtime.kind.payloadValue}",
            )
            try {
                nextSession.start(clientVersion = BuildConfig.VERSION_NAME)
                val becameReady = serverMessageBarrier.run {
                    synchronized(sessionStateLock) {
                        if (isCurrentSessionLocked(generation, nextSession) &&
                            nextSession.isRunning
                        ) {
                            activeSessionReadiness = CodexSessionReadiness.READY
                            true
                        } else {
                            false
                        }
                    }
                }
                check(becameReady) {
                    "Codex app-server disconnected before initialization completed."
                }
            } catch (error: Throwable) {
                serverMessageBarrier.run {
                    synchronized(sessionStateLock) {
                        if (isCurrentSessionLocked(generation, nextSession)) {
                            invalidateServerRequestsLocked(
                                generation = generation,
                                sessionIdentity = nextSession,
                                reason = "connect_failed",
                            )
                            clearActiveSessionLocked()
                        }
                    }
                }
                throw error
            }
        }
        return status()
    }

    suspend fun disconnect(): Map<String, Any?> {
        sessionMutex.withLock {
            val currentSession = session
            val currentGeneration = activeSessionGeneration
            serverMessageBarrier.run {
                synchronized(sessionStateLock) {
                    if (currentSession != null &&
                        currentGeneration != NO_SESSION_GENERATION
                    ) {
                        invalidateServerRequestsLocked(
                            generation = currentGeneration,
                            sessionIdentity = currentSession,
                            reason = "disconnect",
                        )
                    }
                    if (session === currentSession) {
                        clearActiveSessionLocked()
                    }
                }
            }
            currentSession?.disconnect()
            activeTurnsByThreadId.clear()
            finishedNotifyOnceByThread.clear()
        }
        return status()
    }

    suspend fun handleMethod(
        method: String,
        args: Map<String, Any?>,
        callerEngineToken: String? = null,
    ): Any? {
        return when (method) {
            "status" -> status()
            "connect" -> connect()
            "disconnect" -> disconnect()
            "thread/start" -> startThread(args)
            "thread/resume" -> requestWithResolvedThread("thread/resume", args)
            "thread/read" -> requestWithResolvedThread("thread/read", args)
            "thread/list" -> listThreads(args)
            "thread/loaded/list" -> requestWrappedList("thread/loaded/list", args, "threads")
            "thread/archive" -> archiveThread(args, archived = true)
            "thread/unarchive" -> archiveThread(args, archived = false)
            "thread/name/set" -> setThreadName(args)
            "model/list" -> requestWrappedList(
                "model/list",
                args.ifEmpty { mapOf("limit" to 100) },
                "models"
            )
            "collaborationMode/list" -> requestWrappedList(
                "collaborationMode/list",
                args,
                "collaborationModes"
            )
            "config/local/read" -> readLocalConfig()
            "config/local/write" -> writeLocalConfig(args)
            "config/remote/test" -> testRemoteConfig(args)
            "config/remote/fs/list" -> listRemoteDirectories(args)
            "config/remote/fs/read" -> readRemoteFile(args)
            "config/remote/fs/write" -> writeRemoteFile(args)
            "config/remote/fs/delete" -> deleteRemotePath(args)
            "config/remote/fs/move" -> moveRemotePath(args)
            "turn/start" -> startTurn(args)
            "turn/steer" -> steerTurn(args)
            "turn/interrupt" -> interruptTurn(args)
            "review/start" -> startReview(args)
            "account/read" -> request("account/read", null)
            "account/login/start" -> request(
                "account/login/start",
                args.ifEmpty { mapOf("type" to "chatgpt") }
            )
            "account/login/cancel" -> request("account/login/cancel", args)
            "account/rateLimits/read" -> request("account/rateLimits/read", null)
            "respondToServerRequest" -> respondToServerRequest(
                args = args,
                callerEngineToken = callerEngineToken,
            )
            else -> request(method, args)
        }
    }

    private suspend fun startThread(args: Map<String, Any?>): Map<String, Any?> = threadStartMutex.withLock {
        val shouldBindLocally = shouldSyncLocalThreadBindings()
        val cwd = sanitizeCodexAbsolutePath(args.stringValue("cwd")) ?: resolveDefaultCwd()
        val conversationId = args.longValue("conversationId")
        // B25: ThreadStartParams uses SandboxMode kebab string field `sandbox`
        // (not sandboxPolicy object). Keep approvalPolicy + approvalsReviewer.
        val params = linkedMapOf<String, Any?>(
            "cwd" to cwd,
            "approvalPolicy" to (args.stringValue("approvalPolicy") ?: "on-request"),
            "sandbox" to resolveCodexSandboxMode(args)
        )
        args.stringValue("approvalsReviewer")?.let {
            params["approvalsReviewer"] = it
        }
        addCodexOptionalRunParams(params, args)
        if (shouldBindLocally && conversationId != null) {
            pendingThreadStartConversationId = conversationId
        }
        try {
            val response = request("thread/start", params) as Map<String, Any?>
            val threadId = extractThreadId(response) ?: response.stringValue("id")
            var localConversationId: Long? = null
            if (shouldBindLocally && !threadId.isNullOrBlank()) {
                localConversationId = bindingRepository.ensureBinding(
                    threadId = threadId,
                    conversationId = conversationId,
                    cwd = cwd,
                    title = extractThreadTitle(response)
                )
            }
            response.withLocalIds(threadId = threadId, conversationId = localConversationId)
        } finally {
            if (pendingThreadStartConversationId == conversationId) {
                pendingThreadStartConversationId = null
            }
        }
    }

    private suspend fun listThreads(args: Map<String, Any?>): Map<String, Any?> {
        val params = linkedMapOf<String, Any?>()
        args["cursor"]?.let { params["cursor"] = it }
        args["limit"]?.let { params["limit"] = it }
        args["sortKey"]?.let { params["sortKey"] = it }
        params["sourceKinds"] = args["sourceKinds"] ?: DEFAULT_CODEX_THREAD_SOURCE_KINDS
        val response = request("thread/list", params) as Map<String, Any?>
        if (shouldSyncLocalThreadBindings()) {
            syncThreadListResponse(response)
        }
        return response
    }

    private suspend fun requestWithResolvedThread(
        method: String,
        args: Map<String, Any?>
    ): Map<String, Any?> {
        val threadId = resolveThreadId(args)
        val params = linkedMapOf<String, Any?>("threadId" to threadId)
        if (method == "thread/read") {
            args["includeTurns"]?.let { params["includeTurns"] = it }
        }
        val response = request(method, params) as Map<String, Any?>
        if (shouldSyncLocalThreadBindings() && (method == "thread/read" || method == "thread/resume")) {
            syncThreadListResponse(response)
        }
        if (method == "thread/read" || method == "thread/resume") {
            syncActiveTurnSnapshot(threadId, response)
        }
        val activeTurnId = activeTurnsByThreadId[threadId]
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationIdForThread(threadId),
            turnId = activeTurnId,
            active = if (method == "thread/read" || method == "thread/resume") {
                activeTurnId != null
            } else {
                null
            }
        )
    }

    private suspend fun archiveThread(
        args: Map<String, Any?>,
        archived: Boolean
    ): Map<String, Any?> {
        val threadId = resolveThreadId(args)
        val method = if (archived) "thread/archive" else "thread/unarchive"
        val response = request(method, mapOf("threadId" to threadId)) as Map<String, Any?>
        if (shouldSyncLocalThreadBindings()) {
            bindingRepository.setArchived(threadId, archived)
        }
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationIdForThread(threadId)
        )
    }

    private suspend fun setThreadName(args: Map<String, Any?>): Map<String, Any?> {
        val threadId = resolveThreadId(args)
        val name = args.stringValue("name") ?: args.stringValue("threadName") ?: ""
        val response = request(
            "thread/name/set",
            mapOf("threadId" to threadId, "name" to name)
        ) as Map<String, Any?>
        if (shouldSyncLocalThreadBindings()) {
            bindingRepository.updateTitle(threadId, name)
        }
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationIdForThread(threadId)
        )
    }

    private suspend fun requestWrappedList(
        method: String,
        args: Map<String, Any?>,
        listKey: String
    ): Map<String, Any?> {
        val response = request(method, if (args.isEmpty()) null else args)
        return when (response) {
            is Map<*, *> -> response.entries.associate { (key, value) -> key.toString() to value }
            is List<*> -> mapOf(listKey to response)
            else -> mapOf(listKey to emptyList<Any?>(), "raw" to response)
        }
    }

    private suspend fun startTurn(args: Map<String, Any?>): Map<String, Any?> {
        val cwd = sanitizeCodexAbsolutePath(args.stringValue("cwd")) ?: resolveDefaultCwd()
        var threadId = ensureThreadForTurn(args, cwd)
        val params = buildTurnStartParams(
            args = args,
            cwd = cwd,
            threadId = threadId
        )
        val response = try {
            request("turn/start", params) as Map<String, Any?>
        } catch (error: Throwable) {
            if (!shouldRecoverMissingThread(error)) {
                throw error
            }
            Log.w(
                "CodexAppServerManager",
                "Codex turn/start hit a missing thread; creating a fresh thread binding."
            )
            val retryResponse = startThread(args + mapOf("cwd" to cwd))
            threadId = retryResponse["threadId"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                ?: throw error
            params["threadId"] = threadId
            request("turn/start", params) as Map<String, Any?>
        }
        val turnId = extractTurnId(response)
        if (!turnId.isNullOrBlank()) {
            activeTurnsByThreadId[threadId] = turnId
        }
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationIdForThread(threadId),
            turnId = turnId
        )
    }

    private suspend fun startReview(args: Map<String, Any?>): Map<String, Any?> {
        val cwd = sanitizeCodexAbsolutePath(args.stringValue("cwd")) ?: resolveDefaultCwd()
        var threadId = ensureThreadForTurn(args, cwd)
        val params = buildReviewStartParams(
            args = args,
            cwd = cwd,
            threadId = threadId
        )
        val response = try {
            request("review/start", params) as Map<String, Any?>
        } catch (error: Throwable) {
            if (!shouldRecoverMissingThread(error)) {
                throw error
            }
            Log.w(
                "CodexAppServerManager",
                "Codex review/start hit a missing thread; creating a fresh thread binding."
            )
            val retryResponse = startThread(args + mapOf("cwd" to cwd))
            threadId = retryResponse["threadId"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                ?: throw error
            params["threadId"] = threadId
            request("review/start", params) as Map<String, Any?>
        }
        val turnId = extractTurnId(response)
        if (!turnId.isNullOrBlank()) {
            activeTurnsByThreadId[threadId] = turnId
        }
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationIdForThread(threadId),
            turnId = turnId
        )
    }

    private suspend fun steerTurn(args: Map<String, Any?>): Map<String, Any?> {
        val threadId = resolveThreadId(args)
        val expectedTurnId = args.stringValue("expectedTurnId")
            ?: args.stringValue("turnId")
            ?: activeTurnsByThreadId[threadId]
            ?: throw IllegalArgumentException("missing active Codex turn id")
        val response = request(
            "turn/steer",
            mapOf(
                "threadId" to threadId,
                "expectedTurnId" to expectedTurnId,
                "input" to resolveInput(args)
            )
        ) as Map<String, Any?>
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationIdForThread(threadId),
            turnId = expectedTurnId
        )
    }

    private suspend fun interruptTurn(args: Map<String, Any?>): Map<String, Any?> {
        val threadId = resolveThreadId(args)
        val turnId = args.stringValue("turnId")
            ?: activeTurnsByThreadId[threadId]
            ?: throw IllegalArgumentException("missing active Codex turn id")
        val response = request(
            "turn/interrupt",
            mapOf("threadId" to threadId, "turnId" to turnId)
        ) as Map<String, Any?>
        activeTurnsByThreadId.remove(threadId)
        val localConversationId = localConversationIdForThread(threadId)
        // Interrupt RPC may complete before turn_aborted event; single-fire guard
        // prevents a second status-bar notification when the event also arrives.
        notifyCodexTurnTerminalOnce(
            threadId = threadId,
            turnId = turnId,
            title = "Codex task stopped",
            message = "The Codex turn was stopped. Tap to view details.",
            conversationId = localConversationId
        )
        return response.withLocalIds(
            threadId = threadId,
            conversationId = localConversationId,
            turnId = turnId
        )
    }

    private suspend fun respondToServerRequest(
        args: Map<String, Any?>,
        callerEngineToken: String?,
    ): Map<String, Any?> = sessionMutex.withLock {
        val requestId = args["requestId"] ?: args["id"]
            ?: throw IllegalArgumentException("requestId is required")
        val requestedGeneration = args.longValue("sessionGeneration")
        val requestedMethod = args.stringValue("serverRequestMethod")
        val result = args["response"] ?: args["result"]
            ?: throw IllegalArgumentException("response is required")
        val (currentSession, currentGeneration, currentReadiness) =
            synchronized(sessionStateLock) {
                Triple(
                    session,
                    activeSessionGeneration,
                    activeSessionReadiness,
                )
            }
        val responseWriter: (suspend (Any, Any?) -> Unit)? =
            currentSession?.takeIf {
                currentReadiness == CodexSessionReadiness.READY &&
                    it.isRunning
            }?.let { runningSession ->
                { id, response -> runningSession.sendResponse(id, response) }
            }
        val pending = requestedGeneration?.let {
            serverRequests.find(it, requestId)
        }
        val responseResult = try {
            serverRequestResponder.respond(
                requestedGeneration = requestedGeneration,
                activeGeneration = currentGeneration,
                activeSessionIdentity = currentSession,
                requestId = requestId,
                requestedMethod = requestedMethod,
                response = result,
                responseWriter = responseWriter,
            )
        } catch (error: CodexServerRequestResponseException) {
            logServerRequestLifecycle(
                action = "response_rejected",
                engineToken = callerEngineToken,
                generation = requestedGeneration,
                method = pending?.method,
                requestId = requestId,
                resolved = false,
                actionResult = error.errorCode,
            )
            if (error.errorCode == "CODEX_SERVER_RESPONSE_WRITE_FAILED" &&
                currentSession != null &&
                requestedGeneration != null
            ) {
                val restoredPending = synchronized(sessionStateLock) {
                    if (isCurrentSessionLocked(currentGeneration, currentSession) &&
                        requestedGeneration == currentGeneration
                    ) {
                        serverRequests.find(requestedGeneration, requestId)
                            ?.takeIf {
                                it.state == CodexServerRequestState.PENDING
                            }
                    } else {
                        null
                    }
                }
                if (restoredPending != null) {
                    // A replacement stream can subscribe while this request is
                    // RESPONSE_SENDING and therefore correctly miss replay.
                    // Once the write fails back to PENDING, redeliver it; streams
                    // that already saw the prompt reject the duplicate key.
                    emitPendingServerRequest(
                        request = restoredPending,
                        replayed = true,
                    )
                }
            }
            throw error
        }
        logServerRequestLifecycle(
            action = "response_sent",
            engineToken = callerEngineToken,
            request = responseResult.request,
            resolved = responseResult.resolved,
            actionResult = responseResult.actionResult,
        )
        return@withLock linkedMapOf(
            "ok" to true,
            "sessionGeneration" to responseResult.request.sessionGeneration,
            "requestId" to responseResult.request.requestId,
            "serverRequestMethod" to responseResult.request.method,
            "resolved" to responseResult.resolved,
            "actionResult" to responseResult.actionResult,
        )
    }

    private suspend fun readLocalConfig(): Map<String, Any?> =
        configWriteMutex.withLock {
        val remoteConfig = remoteConfigStore.read()
        val command = """
            mkdir -p ${shellQuote(CodexAppServerDefaults.CODEX_HOME)}
            printf '__OMNI_CODEX_CONFIG_START__\n'
            if [ -f ${shellQuote("${CodexAppServerDefaults.CODEX_HOME}/config.toml")} ]; then
              cat ${shellQuote("${CodexAppServerDefaults.CODEX_HOME}/config.toml")}
            fi
            printf '\n__OMNI_CODEX_CONFIG_END__\n'
            printf '__OMNI_CODEX_AUTH_START__\n'
            if [ -f ${shellQuote("${CodexAppServerDefaults.CODEX_HOME}/auth.json")} ]; then
              cat ${shellQuote("${CodexAppServerDefaults.CODEX_HOME}/auth.json")}
            fi
            printf '\n__OMNI_CODEX_AUTH_END__\n'
        """.trimIndent()
        val localRead = runCatching {
            val result = TerminalManager.getInstance(appContext).executeHiddenCommand(
                command = command,
                executorKey = "codex-config-read",
                timeoutMs = 30_000L
            )
            if (!result.isOk || result.exitCode != 0) {
                throw IllegalStateException(
                    result.error.ifBlank { result.rawOutputPreview.ifBlank { "Failed to read Codex config." } }
                )
            }
            result.output
        }
        if (localRead.isFailure && !remoteConfig.enabled) {
            throw localRead.exceptionOrNull()
                ?: IllegalStateException("Failed to read Codex config.")
        }
        val localOutput = localRead.getOrDefault("")
        var configToml = extractMarkedBlock(
            localOutput,
            "__OMNI_CODEX_CONFIG_START__",
            "__OMNI_CODEX_CONFIG_END__"
        )
        val authJson = extractMarkedBlock(
            localOutput,
            "__OMNI_CODEX_AUTH_START__",
            "__OMNI_CODEX_AUTH_END__"
        )
        val commonDefaultsMigrationEligible =
            extractTomlString(configToml, "model").orEmpty().isNotBlank() &&
                extractCodexInternalProviderBaseUrl(configToml).orEmpty().isNotBlank()
        if (commonDefaultsMigrationEligible &&
            !configMigrationPreferences.getBoolean(COMMON_DEFAULTS_MIGRATION_KEY, false)
        ) {
            val migratedToml = migrateCodexCommonDefaultsToml(configToml)
            if (migratedToml != configToml) {
                writeCodexConfigTomlAtomically(migratedToml)
                configToml = migratedToml
            }
            configMigrationPreferences
                .edit()
                .putBoolean(COMMON_DEFAULTS_MIGRATION_KEY, true)
                .apply()
        }
        val serviceTier = extractTomlString(configToml, "service_tier").orEmpty()
        val modelReasoningEffort =
            extractTomlString(configToml, "model_reasoning_effort").orEmpty()
        val defaultGoal = extractTomlString(configToml, "omnimind_default_goal").orEmpty()
        // B30: app-managed context token threshold for Codex top bar (null when missing).
        val contextTokenThreshold =
            extractTomlInt(configToml, "omnimind_context_token_threshold")
        val featuresBody = extractTomlTableBody(configToml, "features")
        // Prefer [features].fast_mode; never treat a missing key as "off by omission".
        val fastMode = extractTomlBoolean(featuresBody, "fast_mode")
            ?: extractTomlBoolean(configToml, "fast_mode")
            ?: false
        // B27: expose features.auto_compaction for settings toggle.
        val autoCompaction = extractTomlBoolean(featuresBody, "auto_compaction")
            ?: extractTomlBoolean(configToml, "auto_compaction")
        // P0/P1: expose top-level web_search (null when omitted / Codex default Cached).
        val webSearchMode =
            normalizeCodexWebSearchMode(extractTomlString(configToml, "web_search"))
        buildCodexLocalConfigPayload(
            model = extractTomlString(configToml, "model").orEmpty(),
            baseUrl = extractCodexInternalProviderBaseUrl(configToml).orEmpty(),
            apiKey = extractOpenAiApiKey(authJson).orEmpty(),
            serviceTier = serviceTier,
            modelReasoningEffort = modelReasoningEffort,
            defaultGoal = defaultGoal,
            fastMode = fastMode,
            autoCompaction = autoCompaction,
            contextTokenThreshold = contextTokenThreshold,
            webSearchMode = webSearchMode,
            remoteConfig = remoteConfig,
            runtime = resolveRuntime().kind.payloadValue
        )
    }

    private suspend fun writeLocalConfig(
        args: Map<String, Any?>,
    ): Map<String, Any?> = configWriteMutex.withLock {
        // Keep connect/disconnect/server responses outside the two-file
        // replacement window so no new local process can observe mixed
        // config.toml/auth.json identities.
        sessionMutex.withLock {
        val expectedModelProvider = args.stringValue("expectedModelProvider")
        val explicitProviderSwitch =
            args.stringValue("providerRecordId").orEmpty().isNotBlank()
        require(
            expectedModelProvider == null ||
                expectedModelProvider == CODEX_INTERNAL_MODEL_PROVIDER
        ) {
            "Codex model provider is fixed to $CODEX_INTERNAL_MODEL_PROVIDER"
        }
        val baseUrl = args.stringValue("baseUrl").orEmpty()
        val model = args.stringValue("model").orEmpty()
        val apiKey = args.stringValue("apiKey").orEmpty()
        val serviceTier = normalizeCodexServiceTier(
            args.stringValue("serviceTier") ?: args.stringValue("service_tier")
        )
        // Only write effort when the caller provided a valid value — do not
        // silently invent xhigh in config.toml.
        val modelReasoningEffort =
            normalizeCodexReasoningEffort(args.stringValue("modelReasoningEffort"))
                .orEmpty()
        val requestedDefaultGoal = args.stringValue("defaultGoal").orEmpty().trim()
        val requestedFastMode = args.booleanValue("fastMode") ?: args.booleanValue("fast_mode")
        val requestedAutoCompaction =
            args.booleanValue("autoCompaction") ?: args.booleanValue("auto_compaction")
        val requestedContextTokenThreshold =
            args.intValue("contextTokenThreshold")
                ?: args.intValue("omnimind_context_token_threshold")
                ?: args.intValue("context_token_threshold")
        // P0/P1: only force web_search when caller provides a known mode; otherwise preserve.
        val requestedWebSearchMode = normalizeCodexWebSearchMode(
            args.stringValue("webSearchMode") ?: args.stringValue("web_search")
        )
        val serviceTierArgPresent =
            args.containsKey("serviceTier") || args.containsKey("service_tier")
        val remoteConfig = CodexRemoteBridgeConfig(
            enabled = args["remoteEnabled"] == true,
            bridgeUrl = args.stringValue("remoteBridgeUrl").orEmpty(),
            authToken = args.stringValue("remoteBridgeToken").orEmpty(),
            cwd = args.stringValue("remoteCwd").orEmpty()
        )
        val localComplete = baseUrl.isNotBlank() && model.isNotBlank() && apiKey.isNotBlank()
        if (remoteConfig.enabled && !remoteConfig.isConfigured) {
            throw IllegalArgumentException("Remote Codex bridge URL and cwd are required.")
        }

        // B36/B37: compare hard identity before write so soft feature toggles
        // (fast_mode / auto_compaction / service_tier / threshold / web_search)
        // can skip session kill — avoids Fast path "thread not found" + reconnect heat.
        // B37: empty/failed reads are unknown, not empty identity (shell race).
        val previousRemoteConfig = remoteConfigStore.read()
        val savedRemoteConfig = remoteConfigStore.write(remoteConfig)
        val existingToml = if (localComplete) {
            readExistingCodexConfigToml()
        } else {
            ""
        }
        val existingAuthJson = if (localComplete) {
            readExistingCodexAuthJson()
        } else {
            ""
        }
        val existingFeatures = extractTomlTableEntries(existingToml, "features")
        val featuresBodyForWrite = extractTomlTableBody(existingToml, "features")
        val existingFastMode = extractTomlBoolean(featuresBodyForWrite, "fast_mode")
        val existingAutoCompaction = extractTomlBoolean(featuresBodyForWrite, "auto_compaction")
        val existingContextTokenThreshold =
            extractTomlInt(existingToml, "omnimind_context_token_threshold")
        val existingServiceTier =
            normalizeCodexServiceTier(extractTomlString(existingToml, "service_tier"))
        val applyCommonDefaultsMigration =
            localComplete &&
                !configMigrationPreferences.getBoolean(
                    COMMON_DEFAULTS_MIGRATION_KEY,
                    false,
                )
        val fastMode = resolveCodexFastMode(
            requestedFastMode = requestedFastMode,
            serviceTier = serviceTier,
            serviceTierArgPresent = serviceTierArgPresent,
            existingFastMode =
                if (applyCommonDefaultsMigration &&
                    requestedFastMode == null &&
                    !serviceTierArgPresent
                ) {
                    false
                } else {
                    existingFastMode
                }
        )
        // B27: only force auto_compaction when caller provides it; otherwise preserve.
        val autoCompaction =
            requestedAutoCompaction
                ?: if (applyCommonDefaultsMigration) true else existingAutoCompaction
        val defaultGoal =
            if (applyCommonDefaultsMigration) "" else requestedDefaultGoal
        // B30: only rewrite threshold when caller provides it; otherwise preserve.
        val contextTokenThreshold =
            (requestedContextTokenThreshold ?: existingContextTokenThreshold)
                ?.let(::clampContextTokenThreshold)
        // P0/P1 S-Default-A: requested mode wins; else preserve existing; both null → omit.
        val existingWebSearchMode =
            normalizeCodexWebSearchMode(extractTomlString(existingToml, "web_search"))
        val webSearchMode = requestedWebSearchMode ?: existingWebSearchMode
        // Fast off must never persist service_tier=fast; other tiers stay independent.
        val effectiveServiceTier = when {
            applyCommonDefaultsMigration && !serviceTierArgPresent ->
                existingServiceTier?.takeUnless { it == "fast" }
            !fastMode && serviceTier == "fast" -> null
            else -> serviceTier
        }
        if (localComplete) {
            val configToml = buildCodexConfigToml(
                baseUrl = baseUrl,
                model = model,
                serviceTier = effectiveServiceTier,
                modelReasoningEffort = modelReasoningEffort,
                defaultGoal = defaultGoal,
                fastMode = fastMode,
                autoCompaction = autoCompaction,
                contextTokenThreshold = contextTokenThreshold,
                webSearchMode = webSearchMode,
                existingFeatures = existingFeatures,
                existingToml = existingToml
            )
            val authJson = JSONObject()
                .put("OPENAI_API_KEY", apiKey)
                .toString(4) + "\n"
            val configPath = "${CodexAppServerDefaults.CODEX_HOME}/config.toml"
            val authPath = "${CodexAppServerDefaults.CODEX_HOME}/auth.json"
            val command = """
                set -eu
                mkdir -p ${shellQuote(CodexAppServerDefaults.CODEX_HOME)}
                umask 077
                config_path=${shellQuote(configPath)}
                auth_path=${shellQuote(authPath)}
                config_tmp="${'$'}config_path.omni-tmp-${'$'}${'$'}"
                auth_tmp="${'$'}auth_path.omni-tmp-${'$'}${'$'}"
                config_backup="${'$'}config_path.omni-backup-${'$'}${'$'}"
                auth_backup="${'$'}auth_path.omni-backup-${'$'}${'$'}"
                config_existed=0
                auth_existed=0
                config_backup_ready=0
                auth_backup_ready=0
                config_replaced=0
                auth_replaced=0
                committed=0
                rollback() {
                  status="${'$'}?"
                  trap - EXIT HUP INT TERM
                  restore_failed=0
                  if [ "${'$'}committed" -eq 0 ]; then
                    if [ "${'$'}config_replaced" -eq 1 ]; then
                      if [ "${'$'}config_existed" -eq 1 ] && \
                         [ "${'$'}config_backup_ready" -eq 1 ]; then
                        if mv -f "${'$'}config_backup" "${'$'}config_path"; then
                          config_backup_ready=0
                        else
                          restore_failed=1
                        fi
                      elif [ "${'$'}config_existed" -eq 0 ]; then
                        rm -f "${'$'}config_path" || restore_failed=1
                      fi
                    fi
                    if [ "${'$'}auth_replaced" -eq 1 ]; then
                      if [ "${'$'}auth_existed" -eq 1 ] && \
                         [ "${'$'}auth_backup_ready" -eq 1 ]; then
                        if mv -f "${'$'}auth_backup" "${'$'}auth_path"; then
                          auth_backup_ready=0
                        else
                          restore_failed=1
                        fi
                      elif [ "${'$'}auth_existed" -eq 0 ]; then
                        rm -f "${'$'}auth_path" || restore_failed=1
                      fi
                    fi
                  fi
                  rm -f "${'$'}config_tmp" "${'$'}auth_tmp" || true
                  if [ "${'$'}config_backup_ready" -eq 0 ] || \
                     [ "${'$'}config_replaced" -eq 0 ]; then
                    rm -f "${'$'}config_backup" || true
                  fi
                  if [ "${'$'}auth_backup_ready" -eq 0 ] || \
                     [ "${'$'}auth_replaced" -eq 0 ]; then
                    rm -f "${'$'}auth_backup" || true
                  fi
                  if [ "${'$'}restore_failed" -eq 1 ]; then
                    printf '%s\n' 'Codex config rollback failed; backup retained.' >&2
                    exit 1
                  fi
                  exit "${'$'}status"
                }
                trap rollback EXIT
                trap 'exit 1' HUP INT TERM
                rm -f "${'$'}config_tmp" "${'$'}auth_tmp" \
                  "${'$'}config_backup" "${'$'}auth_backup"
                printf %s ${shellQuote(configToml)} > "${'$'}config_tmp"
                printf %s ${shellQuote(authJson)} > "${'$'}auth_tmp"
                chmod 600 "${'$'}config_tmp" "${'$'}auth_tmp"
                if [ -f "${'$'}config_path" ]; then
                  config_existed=1
                  cp -p "${'$'}config_path" "${'$'}config_backup"
                  chmod 600 "${'$'}config_backup"
                  config_backup_ready=1
                fi
                if [ -f "${'$'}auth_path" ]; then
                  auth_existed=1
                  cp -p "${'$'}auth_path" "${'$'}auth_backup"
                  chmod 600 "${'$'}auth_backup"
                  auth_backup_ready=1
                fi
                config_replaced=1
                mv -f "${'$'}config_tmp" "${'$'}config_path"
                auth_replaced=1
                mv -f "${'$'}auth_tmp" "${'$'}auth_path"
                chmod 600 "${'$'}config_path" "${'$'}auth_path"
                committed=1
                rm -f "${'$'}config_backup" "${'$'}auth_backup" || true
                trap - EXIT HUP INT TERM
                printf '__OMNI_CODEX_WRITE_OK__\n'
            """.trimIndent()
            val result = TerminalManager.getInstance(appContext).executeHiddenCommand(
                command = command,
                executorKey = "codex-config-write",
                timeoutMs = 30_000L
            )
            if (!result.isOk || result.exitCode != 0) {
                throw IllegalStateException(
                    result.error.ifBlank { result.rawOutputPreview.ifBlank { "Failed to write Codex config." } }
                )
            }
            if (applyCommonDefaultsMigration) {
                configMigrationPreferences
                    .edit()
                    .putBoolean(COMMON_DEFAULTS_MIGRATION_KEY, true)
                    .apply()
            }
        }
        // B36/B37: only kill session when hard identity changes (provider/model/key/remote).
        // Soft toggles (fast_mode, auto_compaction, service_tier, threshold, effort,
        // defaultGoal, web_search) keep the live session so Fast no longer yields
        // thread-not-found.
        // B37 harden: blank readExisting* results are unknown — do not treat as empty
        // identity or first bootstrap while a session is live (shell race/fail).
        val existingTomlKnown = existingToml.isNotBlank()
        val existingAuthKnown = existingAuthJson.isNotBlank()
        val existingModel = extractTomlString(existingToml, "model").orEmpty()
        val existingBaseUrl = extractCodexInternalProviderBaseUrl(existingToml).orEmpty()
        val existingApiKey = extractOpenAiApiKey(existingAuthJson).orEmpty()
        val remoteHardChanged =
            previousRemoteConfig.enabled != savedRemoteConfig.enabled ||
                previousRemoteConfig.bridgeUrl.trim() != savedRemoteConfig.bridgeUrl.trim() ||
                previousRemoteConfig.authToken.trim() != savedRemoteConfig.authToken.trim() ||
                previousRemoteConfig.cwd.trim() != savedRemoteConfig.cwd.trim()
        val localHardChanged = localComplete && (
            (existingTomlKnown && (existingModel != model || existingBaseUrl != baseUrl)) ||
                (existingAuthKnown && existingApiKey != apiKey)
            )
        // First-time local write only when no known toml AND no live session (fail-open soft).
        val hasLiveSession = session != null
        val firstLocalBootstrap = localComplete && !existingTomlKnown && !hasLiveSession
        // A provider switch must not report success while a live session keeps
        // an identity that could not be read. Conservatively reconnect once;
        // ordinary soft preference writes retain the previous fail-open path.
        val providerIdentityUnknown =
            localComplete &&
                explicitProviderSwitch &&
                (!existingTomlKnown || !existingAuthKnown)
        val shouldRestartSession =
            remoteHardChanged ||
                localHardChanged ||
                firstLocalBootstrap ||
                providerIdentityUnknown
        if (shouldRestartSession) {
            val reason = when {
                remoteHardChanged -> "remote-hard"
                localHardChanged -> "local-hard"
                firstLocalBootstrap -> "bootstrap"
                providerIdentityUnknown -> "provider-hard-unknown"
                else -> "unknown"
            }
            Log.i(
                "CodexAppServerManager",
                "B37 writeLocalConfig restart session reason=$reason"
            )
            val currentSession = session
            val currentGeneration = activeSessionGeneration
            serverMessageBarrier.run {
                synchronized(sessionStateLock) {
                    if (currentSession != null &&
                        currentGeneration != NO_SESSION_GENERATION
                    ) {
                        invalidateServerRequestsLocked(
                            generation = currentGeneration,
                            sessionIdentity = currentSession,
                            reason = "session_replaced",
                        )
                    }
                    if (session === currentSession) {
                        clearActiveSessionLocked()
                    }
                }
            }
            currentSession?.disconnect()
            activeTurnsByThreadId.clear()
            finishedNotifyOnceByThread.clear()
        } else {
            // B38 T5: explicit soft-path observability (PLAN soft conf disconnect).
            val softReason = when {
                localComplete && !existingTomlKnown && hasLiveSession -> "soft_toml_unknown"
                else -> "soft"
            }
            Log.i(
                "CodexAppServerManager",
                "B38 writeLocalConfig restart=skipped reason=$softReason hasLiveSession=$hasLiveSession"
            )
        }
        buildCodexLocalConfigPayload(
            model = model,
            baseUrl = baseUrl,
            apiKey = apiKey,
            serviceTier = effectiveServiceTier.orEmpty(),
            modelReasoningEffort = modelReasoningEffort,
            defaultGoal = defaultGoal,
            fastMode = fastMode,
            autoCompaction = autoCompaction,
            contextTokenThreshold = contextTokenThreshold,
            webSearchMode = webSearchMode,
            remoteConfig = savedRemoteConfig,
            runtime = resolveRuntime().kind.payloadValue
        )
        }
    }

    private suspend fun readExistingCodexConfigToml(): String {
        val configPath = "${CodexAppServerDefaults.CODEX_HOME}/config.toml"
        val command = """
            if [ -f ${shellQuote(configPath)} ]; then
              cat ${shellQuote(configPath)}
            fi
        """.trimIndent()
        return runCatching {
            val result = TerminalManager.getInstance(appContext).executeHiddenCommand(
                command = command,
                executorKey = "codex-config-read-existing",
                timeoutMs = 15_000L
            )
            if (!result.isOk || result.exitCode != 0) {
                ""
            } else {
                result.output
            }
        }.getOrDefault("")
    }

    private suspend fun writeCodexConfigTomlAtomically(configToml: String) {
        val configPath = "${CodexAppServerDefaults.CODEX_HOME}/config.toml"
        val tempPath = "$configPath.omni-migration-tmp"
        val command = """
            set -eu
            mkdir -p ${shellQuote(CodexAppServerDefaults.CODEX_HOME)}
            umask 077
            rm -f ${shellQuote(tempPath)}
            printf %s ${shellQuote(configToml)} > ${shellQuote(tempPath)}
            chmod 600 ${shellQuote(tempPath)}
            mv -f ${shellQuote(tempPath)} ${shellQuote(configPath)}
        """.trimIndent()
        val result = TerminalManager.getInstance(appContext).executeHiddenCommand(
            command = command,
            executorKey = "codex-config-common-defaults-migration",
            timeoutMs = 30_000L,
        )
        if (!result.isOk || result.exitCode != 0) {
            throw IllegalStateException(
                result.error.ifBlank {
                    result.rawOutputPreview.ifBlank {
                        "Failed to migrate Codex common defaults."
                    }
                }
            )
        }
    }

    /** B36: read auth.json so soft conf writes can detect hard apiKey identity changes. */
    private suspend fun readExistingCodexAuthJson(): String {
        val authPath = "${CodexAppServerDefaults.CODEX_HOME}/auth.json"
        val command = """
            if [ -f ${shellQuote(authPath)} ]; then
              cat ${shellQuote(authPath)}
            fi
        """.trimIndent()
        return runCatching {
            val result = TerminalManager.getInstance(appContext).executeHiddenCommand(
                command = command,
                executorKey = "codex-auth-read-existing",
                timeoutMs = 15_000L
            )
            if (!result.isOk || result.exitCode != 0) {
                ""
            } else {
                result.output
            }
        }.getOrDefault("")
    }

    private suspend fun testRemoteConfig(args: Map<String, Any?>): Map<String, Any?> {
        val remoteConfig = CodexRemoteBridgeConfig(
            enabled = true,
            bridgeUrl = args.stringValue("remoteBridgeUrl").orEmpty(),
            authToken = args.stringValue("remoteBridgeToken").orEmpty(),
            cwd = args.stringValue("remoteCwd").orEmpty()
        )
        if (!remoteConfig.isConfigured) {
            return linkedMapOf(
                "ok" to false,
                "ready" to false,
                "error" to "Remote Codex bridge URL and cwd are required.",
                "cwd" to remoteConfig.cwd
            )
        }
        val probe = probeCodexRemoteBridge(remoteConfig)
        return linkedMapOf(
            "ok" to probe.ready,
            "ready" to probe.ready,
            "version" to probe.version,
            "error" to probe.error,
            "cwd" to (probe.cwd ?: remoteConfig.cwd)
        )
    }

    private suspend fun listRemoteDirectories(args: Map<String, Any?>): Map<String, Any?> {
        val remoteConfig = remoteConfigFromArgs(args)
        val path = args.stringValue("path") ?: remoteConfig.cwd.takeIf { it.isNotBlank() }
        return listCodexRemoteBridgeDirectory(remoteConfig, path)
    }

    private suspend fun readRemoteFile(args: Map<String, Any?>): Map<String, Any?> {
        return readCodexRemoteBridgeFile(
            config = remoteConfigFromArgs(args),
            path = args.stringValue("path")
        )
    }

    private suspend fun writeRemoteFile(args: Map<String, Any?>): Map<String, Any?> {
        return writeCodexRemoteBridgeFile(
            config = remoteConfigFromArgs(args),
            path = args.stringValue("path"),
            content = args["content"]?.toString().orEmpty()
        )
    }

    private suspend fun deleteRemotePath(args: Map<String, Any?>): Map<String, Any?> {
        return deleteCodexRemoteBridgePath(
            config = remoteConfigFromArgs(args),
            path = args.stringValue("path"),
            recursive = args["recursive"] == true
        )
    }

    private suspend fun moveRemotePath(args: Map<String, Any?>): Map<String, Any?> {
        return moveCodexRemoteBridgePath(
            config = remoteConfigFromArgs(args),
            path = args.stringValue("path"),
            destinationPath = args.stringValue("destinationPath")
        )
    }

    private suspend fun remoteConfigFromArgs(args: Map<String, Any?>): CodexRemoteBridgeConfig {
        val storedConfig = remoteConfigStore.read()
        return CodexRemoteBridgeConfig(
            enabled = true,
            bridgeUrl = args.stringValue("remoteBridgeUrl") ?: storedConfig.bridgeUrl,
            authToken = args.stringValue("remoteBridgeToken") ?: storedConfig.authToken,
            cwd = args.stringValue("remoteCwd") ?: storedConfig.cwd
        )
    }

    private fun buildTurnStartParams(
        args: Map<String, Any?>,
        cwd: String,
        threadId: String
    ): MutableMap<String, Any?> {
        val params = linkedMapOf<String, Any?>(
            "threadId" to threadId,
            "input" to resolveInput(args),
            "cwd" to cwd,
            "approvalPolicy" to (args.stringValue("approvalPolicy") ?: "on-request"),
            // B25: turn/start uses sandboxPolicy object; never pass empty writableRoots.
            "sandboxPolicy" to resolveCodexSandboxPolicy(args["sandboxPolicy"], cwd)
        )
        args.stringValue("approvalsReviewer")?.let {
            params["approvalsReviewer"] = it
        }
        addCodexOptionalRunParams(params, args)
        return params
    }

    private fun buildReviewStartParams(
        args: Map<String, Any?>,
        cwd: String,
        threadId: String
    ): MutableMap<String, Any?> {
        val params = linkedMapOf<String, Any?>(
            "threadId" to threadId,
            "target" to resolveCodexReviewTarget(args["target"]),
            "delivery" to (args.stringValue("delivery") ?: "inline"),
            "cwd" to cwd,
            "approvalPolicy" to (args.stringValue("approvalPolicy") ?: "on-request"),
            // B25: review path same as turn — fill empty writableRoots from cwd.
            "sandboxPolicy" to resolveCodexSandboxPolicy(args["sandboxPolicy"], cwd)
        )
        args.stringValue("approvalsReviewer")?.let {
            params["approvalsReviewer"] = it
        }
        addCodexOptionalRunParams(params, args)
        return params
    }

    private fun shouldRecoverMissingThread(error: Throwable): Boolean {
        val message = error.message?.lowercase().orEmpty()
        return message.contains("thread not found")
    }

    private suspend fun ensureThreadForTurn(args: Map<String, Any?>, cwd: String): String {
        val explicitThreadId = args.stringValue("threadId")
        if (!explicitThreadId.isNullOrBlank()) {
            return explicitThreadId
        }
        if (shouldSyncLocalThreadBindings()) {
            val conversationId = args.longValue("conversationId")
            if (conversationId != null) {
                val binding = bindingRepository.getBindingByConversationId(conversationId)
                if (binding != null) {
                    return binding.threadId
                }
            }
        }
        val response = startThread(args + mapOf("cwd" to cwd))
        return response["threadId"]?.toString()?.takeIf { it.isNotBlank() }
            ?: throw IllegalStateException("thread/start did not return a threadId")
    }

    private fun shouldSyncLocalThreadBindings(): Boolean {
        return activeRuntime != CodexRuntimeKind.REMOTE &&
            resolveRuntime().kind != CodexRuntimeKind.REMOTE
    }

    private suspend fun localConversationIdForThread(threadId: String): Long? {
        if (!shouldSyncLocalThreadBindings()) {
            return null
        }
        return bindingRepository.getBindingByThreadId(threadId)?.conversationId
    }

    private fun syncActiveTurnSnapshot(threadId: String, response: Map<String, Any?>) {
        val active = codexThreadActivity(response)
        val activeTurnId = extractActiveTurnId(response)
        if (active == true && !activeTurnId.isNullOrBlank()) {
            activeTurnsByThreadId[threadId] = activeTurnId
            return
        }
        if (active == false) {
            activeTurnsByThreadId.remove(threadId)
        }
    }

    private suspend fun request(method: String, params: Any?): Any {
        val response = ensureConnectedSession().sendRequest(method, params)
        val error = response["error"]
        if (error != null) {
            throw IllegalStateException(error.toString())
        }
        return response["result"] ?: response
    }

    private suspend fun ensureConnectedSession(): CodexAppServerSession {
        readySessionSnapshot()?.let { return it }
        connect()
        return readySessionSnapshot()
            ?: throw IllegalStateException("Codex app-server is not connected.")
    }

    private fun readySessionSnapshot(): CodexAppServerSession? {
        val runtime = resolveRuntime()
        return synchronized(sessionStateLock) {
            session?.takeIf {
                isCodexSessionReadyForUse(
                    readiness = activeSessionReadiness,
                    transportRunning = it.isRunning,
                    runtimeMatches = activeRuntime == runtime.kind,
                )
            }
        }
    }

    private suspend fun handleServerMessage(
        sourceGeneration: Long,
        sourceSession: CodexAppServerSession,
        message: Map<String, Any?>,
    ) = serverMessageBarrier.run {
        if (!isCurrentSession(sourceGeneration, sourceSession)) {
            Log.w(
                TAG,
                "server_message action=ignored_stale generation=$sourceGeneration " +
                    "method=${extractCodexServerMethod(message)}",
            )
            return@run
        }
        val requestEnvelope = findCodexServerRequestEnvelope(message)
        val extractedMethod = extractCodexServerMethod(message)
        val method = extractedMethod.ifBlank { requestEnvelope?.method.orEmpty() }
        val explicitParams = extractCodexServerParams(message)
        val params = if (explicitParams.isNotEmpty()) {
            explicitParams
        } else {
            syntheticCodexServerParams(message, method)
        }
        val threadId = extractThreadId(message)
        val turnId = extractTurnId(message) ?: extractActiveTurnId(message)
        // Diagnostic: log every server-side method that reaches Kotlin so the
        // user can verify via `adb logcat -s CodexAppServerManager:V` whether
        // commandExecution / rawResponseItem events actually arrive over the
        // bridge. If item/started events for commandExecution are missing
        // here but present in `codex app-server` stdout, the bridge is
        // dropping them; if present here but missing on Flutter side, the
        // EventChannel pipe is the problem.
        val diagItemType = (message["params"] as? Map<*, *>)
            ?.get("item")?.let { it as? Map<*, *> }
            ?.get("type")?.toString()
            ?: (params["item"] as? Map<*, *>)?.get("type")?.toString()
        Log.d(
            TAG,
            "<- generation=$sourceGeneration method=$method itemType=$diagItemType " +
                "threadId=$threadId turnId=$turnId",
        )
        val protocolEventType = if (method == "codex/event") {
            codexProtocolEventType(params)
        } else {
            ""
        }
        if (!threadId.isNullOrBlank() && !turnId.isNullOrBlank() &&
            (method == "turn/started" ||
                protocolEventType == "task_started" ||
                protocolEventType == "turn_started")) {
            activeTurnsByThreadId[threadId] = turnId
            // New turn may notify again after a prior terminal state for this thread.
            finishedNotifyOnceByThread.remove(threadId)
            TaskRuntimeSettings.onTaskStarted(appContext)
        }
        if (!threadId.isNullOrBlank() && method == "thread/status/changed") {
            val active = codexThreadActivity(message)
            if (active == true && !turnId.isNullOrBlank()) {
                activeTurnsByThreadId[threadId] = turnId
                finishedNotifyOnceByThread.remove(threadId)
            } else if (active == false) {
                activeTurnsByThreadId.remove(threadId)
            }
        }
        if (!threadId.isNullOrBlank() &&
            (method == "turn/completed" ||
                protocolEventType == "task_complete" ||
                protocolEventType == "turn_complete" ||
                protocolEventType == "turn_aborted")) {
            activeTurnsByThreadId.remove(threadId)
        }
        if (!threadId.isNullOrBlank() &&
            (method == "error" || method == "turn/failed") &&
            params["willRetry"] != true) {
            // codex app-server emits top-level `error` notifications when a
            // turn fails terminally (no follow-up turn/completed will come).
            // Clear the active turn so subsequent thread/read responses
            // surface active=false to the Flutter side.
            activeTurnsByThreadId.remove(threadId)
        }
        if (!threadId.isNullOrBlank() && method == "thread/closed") {
            activeTurnsByThreadId.remove(threadId)
            finishedNotifyOnceByThread.remove(threadId)
        }

        val localConversationId = syncMessage(method, message, params, threadId)
        when {
            method == "turn/completed" ||
                protocolEventType == "task_complete" ||
                protocolEventType == "turn_complete" -> {
                notifyCodexTurnTerminalOnce(
                    threadId = threadId,
                    turnId = turnId,
                    title = "Codex task completed",
                    message = "Tap to view the completed Codex turn.",
                    conversationId = localConversationId
                )
            }
            protocolEventType == "turn_aborted" ||
                method == "turn/interrupted" ||
                method == "turn/interrupt/completed" -> {
                notifyCodexTurnTerminalOnce(
                    threadId = threadId,
                    turnId = turnId,
                    title = "Codex task stopped",
                    message = "The Codex turn was stopped. Tap to view details.",
                    conversationId = localConversationId
                )
            }
            (method == "error" || method == "turn/failed") &&
                params["willRetry"] != true -> {
                notifyCodexTurnTerminalOnce(
                    threadId = threadId,
                    turnId = turnId,
                    title = "Codex task failed",
                    message = "The Codex turn failed. Tap to view details.",
                    conversationId = localConversationId
                )
            }
        }
        synchronized(sessionStateLock) {
            if (!isCurrentSessionLocked(sourceGeneration, sourceSession)) {
                Log.w(
                    TAG,
                    "server_message action=ignored_after_session_change " +
                        "generation=$sourceGeneration method=$method",
                )
                return@synchronized
            }

            var lifecycleRequest: CodexPendingServerRequest? = null
            var lifecycleRequestId: Any? = null
            var lifecycleMethod: String? = null
            var lifecycleResolved: Boolean? = null
            var lifecycleActionResult: String? = null
            var pendingDeliveryRequest: CodexPendingServerRequest? = null
            var terminalRequestKey: String? = null

            if (method == SERVER_REQUEST_RESOLVED_METHOD) {
                lifecycleRequestId = extractResolvedServerRequestId(message, params)
                if (lifecycleRequestId != null) {
                    lifecycleRequest = serverRequests.resolve(
                        sessionGeneration = sourceGeneration,
                        sessionIdentity = sourceSession,
                        requestId = lifecycleRequestId,
                    )
                }
                terminalRequestKey = lifecycleRequest?.requestKey
                    ?: lifecycleRequestId?.let {
                        codexServerRequestKey(sourceGeneration, it)
                    }
                lifecycleMethod = lifecycleRequest?.method
                    ?: params.stringValue("serverRequestMethod")
                    ?: params.stringValue("method")
                lifecycleResolved = true
                lifecycleActionResult = extractServerRequestActionResult(params)
                logServerRequestLifecycle(
                    action = if (lifecycleRequest == null) {
                        "resolved_without_pending"
                    } else {
                        "resolved"
                    },
                    generation = sourceGeneration,
                    method = lifecycleMethod,
                    requestId = lifecycleRequestId,
                    resolved = true,
                    actionResult = lifecycleActionResult,
                )
            } else if (requestEnvelope != null) {
                val registration = serverRequests.register(
                    sessionGeneration = sourceGeneration,
                    sessionIdentity = sourceSession,
                    requestId = requestEnvelope.requestId,
                    method = requestEnvelope.method,
                    threadId = threadId,
                    turnId = turnId,
                    eventMethod = method,
                    params = params,
                    message = message,
                    conversationId = localConversationId,
                )
                lifecycleRequest = registration.request
                lifecycleRequestId = registration.request.requestId
                lifecycleMethod = registration.request.method
                lifecycleResolved = false
                lifecycleActionResult = if (registration.isNew) {
                    "pending"
                } else {
                    "duplicate_ignored"
                }
                logServerRequestLifecycle(
                    action = if (registration.isNew) "registered" else "duplicate_ignored",
                    request = registration.request,
                    resolved = false,
                    actionResult = lifecycleActionResult,
                )
                if (!registration.isNew) {
                    return@synchronized
                }
                pendingDeliveryRequest = registration.request
            }

            if (method == "codex/disconnected") {
                invalidateServerRequestsLocked(
                    generation = sourceGeneration,
                    sessionIdentity = sourceSession,
                    reason = "connection_exit",
                )
                clearActiveSessionLocked()
                activeTurnsByThreadId.clear()
                finishedNotifyOnceByThread.clear()
            }

            val event = linkedMapOf<String, Any?>(
                "method" to method,
                "workspaceId" to CodexAppServerSession.DEFAULT_WORKSPACE_ID,
                "sessionGeneration" to sourceGeneration,
                "threadId" to threadId,
                "turnId" to turnId,
                "conversationId" to localConversationId,
                "params" to params,
                "message" to message,
            )
            if (lifecycleRequestId != null) {
                event["requestId"] = lifecycleRequestId
                event["serverRequestMethod"] = lifecycleMethod
                event["resolved"] = lifecycleResolved
                event["actionResult"] = lifecycleActionResult
            }
            val requestKey = pendingDeliveryRequest?.requestKey
                ?: terminalRequestKey
            if (requestKey != null) {
                event["serverRequestKey"] = requestKey
            }
            pendingDeliveryRequest?.let { pending ->
                event["serverRequestDeliveryKey"] =
                    codexPendingServerRequestDeliveryKey(
                        pending.requestKey,
                    )
                event["serverRequestState"] =
                    pending.state.name.lowercase()
                event["replayed"] = false
            }
            emitEvent(
                event = event,
                pendingRequest = pendingDeliveryRequest,
            )
        }
    }

    /**
     * B29: fire onTaskFinished + status-bar notify at most once per thread turn terminal.
     * Covers complete / stop(abort+interrupt RPC) / fail without double-notify when both
     * interrupt RPC and turn_aborted (or error + turn/failed) arrive for the same turn.
     */
    private fun notifyCodexTurnTerminalOnce(
        threadId: String?,
        turnId: String?,
        title: String,
        message: String,
        conversationId: Long?
    ): Boolean {
        if (!threadId.isNullOrBlank()) {
            val token = turnId?.takeIf { it.isNotBlank() } ?: "terminal"
            val previous = finishedNotifyOnceByThread.putIfAbsent(threadId, token)
            if (previous != null) {
                return false
            }
        }
        TaskRuntimeSettings.onTaskFinished(appContext)
        TaskRuntimeSettings.notifyTaskFinished(
            context = appContext,
            title = title,
            message = message,
            conversationId = conversationId,
            conversationMode = "codex"
        )
        return true
    }

    private suspend fun syncMessage(
        method: String,
        message: Map<String, Any?>,
        params: Map<String, Any?>,
        threadId: String?
    ): Long? {
        if (!shouldSyncLocalThreadBindings()) {
            return null
        }
        return when (method) {
            "thread/started" -> {
                val thread = params.mapValue("thread")
                val resolvedThreadId = thread.stringValue("id") ?: threadId
                if (resolvedThreadId.isNullOrBlank()) {
                    null
                } else {
                    bindingRepository.ensureBinding(
                        threadId = resolvedThreadId,
                        conversationId = pendingThreadStartConversationId,
                        cwd = sanitizeCodexAbsolutePath(thread.stringValue("cwd"))
                            ?: sanitizeCodexAbsolutePath(params.stringValue("cwd"))
                            ?: resolveDefaultCwd(),
                        title = extractThreadTitle(message)
                    )
                }
            }
            "thread/name/updated" -> {
                val resolvedThreadId = threadId ?: params.stringValue("threadId") ?: params.stringValue("thread_id")
                if (!resolvedThreadId.isNullOrBlank()) {
                    bindingRepository.updateTitle(
                        resolvedThreadId,
                        params.stringValue("threadName")
                            ?: params.stringValue("thread_name")
                            ?: params.stringValue("name")
                            ?: params.stringValue("title")
                    )
                    bindingRepository.getBindingByThreadId(resolvedThreadId)?.conversationId
                } else {
                    null
                }
            }
            "thread/archived" -> {
                threadId?.let {
                    bindingRepository.setArchived(it, true)
                    bindingRepository.getBindingByThreadId(it)?.conversationId
                }
            }
            "thread/unarchived" -> {
                threadId?.let {
                    bindingRepository.setArchived(it, false)
                    bindingRepository.getBindingByThreadId(it)?.conversationId
                }
            }
            else -> {
                if (!threadId.isNullOrBlank()) {
                    bindingRepository.getBindingByThreadId(threadId)?.conversationId
                } else {
                    null
                }
            }
        }
    }

    private suspend fun syncThreadListResponse(response: Map<String, Any?>) {
        collectThreadEntries(response).forEach { entry ->
            bindingRepository.ensureBinding(
                threadId = entry.threadId,
                cwd = sanitizeCodexAbsolutePath(entry.cwd) ?: resolveDefaultCwd(),
                title = entry.title,
                archived = entry.archived
            )
        }
    }

    private suspend fun allocateSessionGeneration(): Long =
        withContext(Dispatchers.IO) {
            synchronized(sessionGenerationLock) {
                val previous = sessionGenerationPreferences.getLong(
                    SESSION_GENERATION_KEY,
                    NO_SESSION_GENERATION,
                )
                val generation = nextCodexSessionGeneration(
                    previousPersisted = previous,
                    nowMillis = System.currentTimeMillis(),
                )
                check(
                    sessionGenerationPreferences.edit()
                        .putLong(SESSION_GENERATION_KEY, generation)
                        .commit(),
                ) {
                    "Failed to persist Codex session generation."
                }
                generation
            }
        }

    /** Must be called while [sessionStateLock] is held. */
    private fun clearActiveSessionLocked() {
        session = null
        activeSessionGeneration = NO_SESSION_GENERATION
        activeRuntime = null
        activeSessionReadiness = CodexSessionReadiness.DISCONNECTED
    }

    private fun isCurrentSession(
        generation: Long,
        sessionIdentity: CodexAppServerSession,
    ): Boolean = synchronized(sessionStateLock) {
        isCurrentSessionLocked(generation, sessionIdentity)
    }

    private fun isCurrentSessionLocked(
        generation: Long,
        sessionIdentity: CodexAppServerSession,
    ): Boolean {
        return generation != NO_SESSION_GENERATION &&
            activeSessionGeneration == generation &&
            session === sessionIdentity
    }

    /**
     * Must be called while [sessionStateLock] is held so registration and the
     * invalidation event are ordered against messages from the replacement
     * session.
     */
    private fun invalidateServerRequestsLocked(
        generation: Long,
        sessionIdentity: CodexAppServerSession,
        reason: String,
    ) {
        serverRequests.invalidateGeneration(
            sessionGeneration = generation,
            sessionIdentity = sessionIdentity,
        ).forEach { request ->
            logServerRequestLifecycle(
                action = "invalidated",
                request = request,
                resolved = false,
                actionResult = "invalidated",
                reason = reason,
            )
            val params = linkedMapOf<String, Any?>(
                "sessionGeneration" to request.sessionGeneration,
                "oldGeneration" to request.sessionGeneration,
                "requestId" to request.requestId,
                "serverRequestMethod" to request.method,
                "serverRequestKey" to request.requestKey,
                "reason" to reason,
                "resolved" to false,
                "actionResult" to "invalidated",
            )
            emitEvent(
                event = linkedMapOf(
                    "method" to SERVER_REQUEST_INVALIDATED_METHOD,
                    "workspaceId" to CodexAppServerSession.DEFAULT_WORKSPACE_ID,
                    "sessionGeneration" to request.sessionGeneration,
                    "oldGeneration" to request.sessionGeneration,
                    "requestId" to request.requestId,
                    "serverRequestMethod" to request.method,
                    "serverRequestKey" to request.requestKey,
                    "threadId" to request.threadId,
                    "turnId" to request.turnId,
                    "conversationId" to request.conversationId,
                    "reason" to reason,
                    "resolved" to false,
                    "actionResult" to "invalidated",
                    "params" to params,
                    "message" to emptyMap<String, Any?>(),
                ),
            )
        }
    }

    private fun logServerRequestLifecycle(
        action: String,
        request: CodexPendingServerRequest,
        engineToken: String? = null,
        resolved: Boolean,
        actionResult: String,
        reason: String? = null,
    ) {
        logServerRequestLifecycle(
            action = action,
            engineToken = engineToken,
            generation = request.sessionGeneration,
            method = request.method,
            requestId = request.requestId,
            resolved = resolved,
            actionResult = actionResult,
            reason = reason,
        )
    }

    private fun logServerRequestLifecycle(
        action: String,
        engineToken: String? = null,
        generation: Long?,
        method: String?,
        requestId: Any?,
        resolved: Boolean,
        actionResult: String,
        reason: String? = null,
    ) {
        Log.i(
            TAG,
            "server_request action=$action engineToken=${engineToken ?: "none"} " +
                "generation=${generation ?: NO_SESSION_GENERATION} " +
                "method=${method ?: "unknown"} id=${requestId ?: "unknown"} " +
                "resolved=$resolved actionResult=$actionResult reason=${reason ?: "none"}",
        )
    }

    private fun emitPendingServerRequest(
        request: CodexPendingServerRequest,
        replayed: Boolean,
    ) {
        emitEvent(
            event = buildCodexPendingServerRequestEvent(
                request = request,
                workspaceId = CodexAppServerSession.DEFAULT_WORKSPACE_ID,
                replayed = replayed,
            ),
            pendingRequest = request,
        )
    }

    private fun emitEvent(
        event: Map<String, Any?>,
        pendingRequest: CodexPendingServerRequest? = null,
    ) {
        mainHandler.post {
            val listeners = eventListeners.snapshot()
            listeners.forEach { registration ->
                deliverEventToRegistration(
                    registration = registration,
                    event = event,
                    pendingRequest = pendingRequest,
                    deliveryAction = if (event["replayed"] == true) {
                        "event_replayed"
                    } else {
                        "event_dispatched"
                    },
                )
            }
        }
    }

    private fun deliverEventToRegistration(
        registration: CodexEventListenerRegistration,
        event: Map<String, Any?>,
        pendingRequest: CodexPendingServerRequest? = null,
        deliveryAction: String,
    ) {
        try {
            val delivered = if (pendingRequest == null) {
                eventListeners.deliver(registration, event)
            } else {
                // Validate PENDING and claim this stream's delivery key at the
                // same linearization point as response claim/resolve/invalidate.
                // The external EventSink callback runs after that lock is released.
                val claimed = serverRequests.claimPendingDelivery(
                    request = pendingRequest,
                    registration = registration,
                )
                if (!claimed) {
                    false
                } else {
                    eventListeners.deliver(
                        registration = registration,
                        event = event,
                        pendingDeliveryPreclaimed = true,
                    )
                }
            }
            if (!delivered) {
                if (pendingRequest != null) {
                    logServerRequestLifecycle(
                        action = "event_pending_skipped",
                        engineToken = registration.engineToken,
                        request = pendingRequest,
                        resolved = false,
                        actionResult = "not_pending_or_duplicate",
                    )
                }
                return
            }
            if (event["requestId"] != null) {
                logServerRequestLifecycle(
                    action = deliveryAction,
                    engineToken = registration.engineToken,
                    generation = (event["sessionGeneration"] as? Number)?.toLong(),
                    method = event["serverRequestMethod"]?.toString(),
                    requestId = event["requestId"],
                    resolved = event["resolved"] == true,
                    actionResult = event["actionResult"]?.toString() ?: "delivered",
                    reason = event["reason"]?.toString(),
                )
            }
        } catch (error: Throwable) {
            Log.e(
                TAG,
                "event_listener action=delivery_failed " +
                    "engineToken=${registration.engineToken} " +
                    "streamToken=${registration.streamToken} " +
                    "method=${event["method"]}",
                error,
            )
        }
    }

    private suspend fun probeCodex(): CodexProbe {
        return runCatching {
            val terminalManager = TerminalManager.getInstance(appContext)
            val result = terminalManager.executeHiddenCommand(
                command = EnvironmentSetupLogic.buildInventoryProbeCommand(listOf("codex")),
                executorKey = "codex-probe",
                timeoutMs = 30_000L
            )
            val parsed = EnvironmentSetupLogic.parseInventoryProbeOutput(result.output)
            val codex = parsed["codex"]
            CodexProbe(
                ready = codex?.ready == true,
                version = codex?.version,
                error = if (result.exitCode == 0) null else result.error.ifBlank { result.rawOutputPreview }
            )
        }.getOrElse { error ->
            CodexProbe(
                ready = false,
                version = null,
                error = error.message ?: error.javaClass.simpleName
            )
        }
    }

    private suspend fun probeRemoteCodex(config: CodexRemoteBridgeConfig): CodexProbe {
        val probe = probeCodexRemoteBridge(config)
        return CodexProbe(
            ready = probe.ready,
            version = probe.version,
            error = probe.error,
            details = probe.details
        )
    }

    private suspend fun resolveDefaultCwd(): String {
        val runtime = resolveRuntime()
        if (runtime.kind == CodexRuntimeKind.REMOTE) {
            return runtime.remoteConfig.cwd.trim()
        }
        return runCatching {
            val workspaceRoot = AgentWorkspaceManager.rootDirectory(appContext)
            workspaceRoot.mkdirs()
            if (workspaceRoot.exists() && workspaceRoot.isDirectory) {
                CodexAppServerDefaults.DEFAULT_WORKSPACE_CWD
            } else {
                CodexAppServerDefaults.FALLBACK_CWD
            }
        }.getOrNull() ?: CodexAppServerDefaults.FALLBACK_CWD
    }

    private fun resolveRuntime(): CodexRuntime {
        val remoteConfig = remoteConfigStore.read()
        return if (remoteConfig.enabled) {
            CodexRuntime(CodexRuntimeKind.REMOTE, remoteConfig)
        } else {
            CodexRuntime(CodexRuntimeKind.LOCAL, remoteConfig)
        }
    }

    private suspend fun resolveThreadId(args: Map<String, Any?>): String {
        val explicit = args.stringValue("threadId") ?: args.stringValue("thread_id")
        if (!explicit.isNullOrBlank()) {
            return explicit
        }
        if (!shouldSyncLocalThreadBindings()) {
            throw IllegalArgumentException("threadId is required for remote Codex sessions")
        }
        val conversationId = args.longValue("conversationId")
            ?: throw IllegalArgumentException("threadId or conversationId is required")
        val binding = bindingRepository.getBindingByConversationId(conversationId)
            ?: throw IllegalArgumentException("Codex thread binding not found for conversation $conversationId")
        return binding.threadId
    }

    private fun resolveInput(args: Map<String, Any?>): List<Map<String, Any?>> {
        val rawInput = args["input"]
        if (rawInput is List<*>) {
            return rawInput
                .mapNotNull { it as? Map<*, *> }
                .map { entry ->
                    LinkedHashMap<String, Any?>().apply {
                        entry.entries.forEach { (key, value) ->
                            put(key.toString(), value)
                        }
                        if (this["type"]?.toString() == "text" && !containsKey("text_elements")) {
                            put("text_elements", emptyList<Map<String, Any?>>())
                        }
                    }
                }
                .filter { it.isNotEmpty() }
        }
        val text = args.stringValue("text") ?: args.stringValue("message") ?: ""
        val trimmed = text.trim()
        require(trimmed.isNotEmpty()) { "Codex turn input is empty" }
        return buildCodexTextInput(trimmed)
    }

    private data class CodexProbe(
        val ready: Boolean,
        val version: String?,
        val error: String?,
        val details: Map<String, Any?> = emptyMap()
    )

    companion object {
        private const val TAG = "CodexAppServerManager"
        private const val NO_SESSION_GENERATION = 0L
        private const val SESSION_GENERATION_PREFERENCES =
            "codex_app_server_lifecycle"
        private const val SESSION_GENERATION_KEY = "last_session_generation"
        private const val CONFIG_MIGRATION_PREFERENCES =
            "codex_config_migrations"
        private const val COMMON_DEFAULTS_MIGRATION_KEY =
            "common_defaults_v1"
        private const val SERVER_REQUEST_RESOLVED_METHOD = "serverRequest/resolved"
        private const val SERVER_REQUEST_INVALIDATED_METHOD = "serverRequest/invalidated"

        @Volatile
        private var INSTANCE: CodexAppServerManager? = null

        fun getInstance(context: Context): CodexAppServerManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: CodexAppServerManager(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }
}

private data class CodexRuntime(
    val kind: CodexRuntimeKind,
    val remoteConfig: CodexRemoteBridgeConfig
)

private enum class CodexRuntimeKind(val payloadValue: String) {
    LOCAL("local"),
    REMOTE("remote")
}

private data class CodexThreadListEntry(
    val threadId: String,
    val cwd: String?,
    val title: String?,
    val archived: Boolean?
)

private data class CodexServerRequestEnvelope(
    val requestId: Any,
    val method: String,
)

private fun findCodexServerRequestEnvelope(
    value: Any?,
    depth: Int = 0,
): CodexServerRequestEnvelope? {
    if (depth > 5) {
        return null
    }
    val map = value.asStringMap() ?: return null
    val directMethod = map["method"]?.toString()?.trim().orEmpty()
    val directId = map["id"]
    if (directMethod.isNotEmpty() &&
        directId != null &&
        !map.containsKey("result") &&
        !map.containsKey("error")
    ) {
        return CodexServerRequestEnvelope(
            requestId = directId,
            method = directMethod,
        )
    }
    for (key in listOf("message", "payload", "event", "data", "body")) {
        findCodexServerRequestEnvelope(map[key], depth + 1)?.let { return it }
    }
    return null
}

private fun extractResolvedServerRequestId(
    message: Map<String, Any?>,
    params: Map<String, Any?>,
): Any? {
    return params["requestId"]
        ?: params["request_id"]
        ?: params["id"]
        ?: message["requestId"]
        ?: message["request_id"]
        ?: params.mapValue("request")["id"]
        ?: message.mapValue("request")["id"]
}

private fun extractServerRequestActionResult(params: Map<String, Any?>): String {
    val value = params["actionResult"]
        ?: params["result"]
        ?: params["status"]
        ?: params["outcome"]
        ?: params["decision"]
        ?: "resolved"
    return value.toString().take(240)
}

internal fun Map<String, Any?>.withLocalIds(
    threadId: String?,
    conversationId: Long?,
    turnId: String? = null,
    active: Boolean? = null
): Map<String, Any?> {
    val result = LinkedHashMap(this)
    if (!threadId.isNullOrBlank()) {
        result["threadId"] = threadId
    }
    if (conversationId != null) {
        result["conversationId"] = conversationId
    }
    if (!turnId.isNullOrBlank()) {
        result["turnId"] = turnId
        if (active == true) {
            result["activeTurnId"] = turnId
        }
    }
    if (active != null) {
        result["active"] = active
    }
    return result
}

internal fun sanitizeCodexAbsolutePath(raw: String?): String? {
    val source = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return source
        .lineSequence()
        .map { it.trim() }
        .lastOrNull { line ->
            line.startsWith("/") && line.none { char -> char.isISOControl() }
        }
}

internal fun buildCodexTextInput(text: String): List<Map<String, Any?>> {
    val trimmed = text.trim()
    require(trimmed.isNotEmpty()) { "Codex turn input is empty" }
    return listOf(
        linkedMapOf(
            "type" to "text",
            "text" to trimmed,
            "text_elements" to emptyList<Map<String, Any?>>()
        )
    )
}

internal fun buildDefaultCodexSandboxPolicy(cwd: String): Map<String, Any?> {
    val writableRoot = sanitizeCodexAbsolutePath(cwd) ?: CodexAppServerDefaults.FALLBACK_CWD
    return linkedMapOf(
        "type" to "workspaceWrite",
        "writableRoots" to listOf(writableRoot),
        "networkAccess" to true,
        "excludeTmpdirEnvVar" to false,
        "excludeSlashTmp" to false
    )
}

/**
 * B25: ThreadStartParams / ThreadResumeParams / ThreadForkParams use
 * SandboxMode kebab string (`sandbox`), not SandboxPolicy object.
 */
internal fun resolveCodexSandboxMode(args: Map<String, Any?>): String {
    val explicit = args.stringValue("sandbox")?.trim().orEmpty()
    if (explicit.isNotEmpty()) {
        return normalizeCodexSandboxMode(explicit)
    }
    val policyType = (args["sandboxPolicy"] as? Map<*, *>)
        ?.get("type")
        ?.toString()
    return sandboxModeFromPolicyType(policyType)
}

internal fun normalizeCodexSandboxMode(raw: String): String {
    val trimmed = raw.trim()
    when (trimmed) {
        "dangerFullAccess" -> return "danger-full-access"
        "readOnly" -> return "read-only"
        "workspaceWrite" -> return "workspace-write"
    }
    return when (trimmed.lowercase().replace('_', '-')) {
        "danger-full-access", "dangerfullaccess" -> "danger-full-access"
        "read-only", "readonly" -> "read-only"
        "workspace-write", "workspacewrite" -> "workspace-write"
        else -> "workspace-write"
    }
}

internal fun sandboxModeFromPolicyType(type: String?): String {
    val normalized = type?.trim().orEmpty()
    return when (normalized) {
        "dangerFullAccess" -> "danger-full-access"
        "readOnly" -> "read-only"
        "workspaceWrite", "" -> "workspace-write"
        else -> normalizeCodexSandboxMode(normalized)
    }
}

/**
 * B25: For turn/start and settings that take SandboxPolicy object — never emit
 * empty writableRoots (overrides native cwd-rooted default → no exec / no popup).
 */
internal fun resolveCodexSandboxPolicy(policy: Any?, cwd: String): Map<String, Any?> {
    val source = policy as? Map<*, *>
    if (source == null) {
        return buildDefaultCodexSandboxPolicy(cwd)
    }
    val type = source["type"]?.toString()?.trim().orEmpty()
    if (type == "dangerFullAccess") {
        return linkedMapOf("type" to "dangerFullAccess")
    }
    if (type == "readOnly") {
        val out = linkedMapOf<String, Any?>("type" to "readOnly")
        (source["networkAccess"] as? Boolean)?.let { out["networkAccess"] = it }
        return out
    }
    // workspaceWrite (default) or unknown — ensure non-empty roots.
    val roots = when (val raw = source["writableRoots"]) {
        is List<*> -> raw.mapNotNull { item ->
            item?.toString()?.trim()?.takeIf { it.startsWith("/") }
        }
        else -> emptyList()
    }
    val fallbackRoot = sanitizeCodexAbsolutePath(cwd)
        ?: CodexAppServerDefaults.DEFAULT_WORKSPACE_CWD
    val effectiveRoots = if (roots.isEmpty()) listOf(fallbackRoot) else roots
    return linkedMapOf(
        "type" to if (type.isEmpty()) "workspaceWrite" else type,
        "writableRoots" to effectiveRoots,
        "networkAccess" to (source["networkAccess"] as? Boolean ?: true),
        "excludeTmpdirEnvVar" to (source["excludeTmpdirEnvVar"] as? Boolean ?: false),
        "excludeSlashTmp" to (source["excludeSlashTmp"] as? Boolean ?: false)
    )
}

internal fun addCodexOptionalRunParams(
    params: MutableMap<String, Any?>,
    args: Map<String, Any?>
) {
    args["model"]?.let { params["model"] = it }
    args["effort"]?.let { params["effort"] = it }
    resolveCodexCollaborationMode(args)?.let { params["collaborationMode"] = it }
    args["serviceTier"]?.let { params["serviceTier"] = it }
}

internal fun resolveCodexCollaborationMode(args: Map<String, Any?>): Map<String, Any?>? {
    val rawMode = args["collaborationMode"] ?: return null
    val source = rawMode.asStringMap()
    val mode = when {
        source != null -> {
            source.stringValue("mode")
                ?: source.stringValue("value")
                ?: source.stringValue("name")
        }
        rawMode is String -> rawMode.trim()
        else -> rawMode.toString().trim()
    }?.normalizeCodexCollaborationModeKind() ?: return null

    val sourceSettings = source?.mapValue("settings").orEmpty()
    val model = sourceSettings.stringValue("model")
        ?: source?.stringValue("model")
        ?: args.stringValue("model")
        ?: return null
    val reasoningEffort = sourceSettings.stringValue("reasoning_effort")
        ?: sourceSettings.stringValue("reasoningEffort")
        ?: source?.stringValue("reasoning_effort")
        ?: source?.stringValue("reasoningEffort")
        ?: args.stringValue("effort")
    val developerInstructions = sourceSettings.stringValue("developer_instructions")
        ?: sourceSettings.stringValue("developerInstructions")
        ?: source?.stringValue("developer_instructions")
        ?: source?.stringValue("developerInstructions")

    val settings = linkedMapOf<String, Any?>("model" to model)
    reasoningEffort?.let { settings["reasoning_effort"] = it }
    developerInstructions?.let { settings["developer_instructions"] = it }
    return linkedMapOf(
        "mode" to mode,
        "settings" to settings
    )
}

private fun Any?.asStringMap(): Map<String, Any?>? {
    val raw = this as? Map<*, *> ?: return null
    return raw.entries.associate { (key, value) -> key.toString() to value }
}

private fun String.normalizeCodexCollaborationModeKind(): String? {
    val normalized = trim().lowercase()
    if (normalized.isEmpty()) {
        return null
    }
    return when {
        normalized == "plan" || normalized.contains("plan") -> "plan"
        normalized == "default" -> "default"
        else -> normalized
    }
}

private fun buildCodexLocalConfigPayload(
    model: String,
    baseUrl: String,
    apiKey: String,
    serviceTier: String = "",
    modelReasoningEffort: String = "",
    defaultGoal: String = "",
    fastMode: Boolean = false,
    autoCompaction: Boolean? = null,
    contextTokenThreshold: Int? = null,
    webSearchMode: String? = null,
    remoteConfig: CodexRemoteBridgeConfig,
    runtime: String
): Map<String, Any?> {
    return linkedMapOf(
        "codexHome" to CodexAppServerDefaults.CODEX_HOME,
        "modelProvider" to CODEX_INTERNAL_MODEL_PROVIDER,
        "model" to model,
        "baseUrl" to baseUrl,
        "apiKey" to apiKey,
        "serviceTier" to serviceTier,
        "modelReasoningEffort" to modelReasoningEffort,
        "defaultGoal" to defaultGoal,
        "fastMode" to fastMode,
        "autoCompaction" to autoCompaction,
        "contextTokenThreshold" to contextTokenThreshold,
        "webSearchMode" to webSearchMode,
        "remoteEnabled" to remoteConfig.enabled,
        "remoteBridgeUrl" to remoteConfig.bridgeUrl,
        "remoteBridgeToken" to remoteConfig.authToken,
        "remoteCwd" to remoteConfig.cwd,
        "remoteConfigured" to remoteConfig.isConfigured,
        "runtime" to runtime
    )
}

/**
 * One-time migration for app-wide Codex defaults. Provider endpoint, model,
 * approval/sandbox keys, hooks, and unrelated tables are preserved.
 */
internal fun migrateCodexCommonDefaultsToml(existingToml: String): String {
    if (existingToml.isBlank()) {
        return existingToml
    }
    val model = extractTomlString(existingToml, "model").orEmpty()
    val baseUrl = extractCodexInternalProviderBaseUrl(existingToml).orEmpty()
    if (model.isBlank() || baseUrl.isBlank()) {
        return existingToml
    }
    // Do not force web_search; preserve existing when present (S-Default-A omit otherwise).
    val existingWebSearch =
        normalizeCodexWebSearchMode(extractTomlString(existingToml, "web_search"))
    return buildCodexConfigToml(
        baseUrl = baseUrl,
        model = model,
        serviceTier =
            normalizeCodexServiceTier(extractTomlString(existingToml, "service_tier"))
                ?.takeUnless { it == "fast" },
        modelReasoningEffort =
            extractTomlString(existingToml, "model_reasoning_effort").orEmpty(),
        defaultGoal = "",
        fastMode = false,
        autoCompaction = true,
        contextTokenThreshold =
            extractTomlInt(existingToml, "omnimind_context_token_threshold"),
        webSearchMode = existingWebSearch,
        existingFeatures =
            extractTomlTableEntries(existingToml, "features"),
        existingToml = existingToml,
    )
}

internal fun extractCodexInternalProviderBaseUrl(source: String): String? {
    val providerBody = extractTomlTableBody(
        source,
        "model_providers.$CODEX_INTERNAL_MODEL_PROVIDER",
    )
    return extractTomlString(providerBody, "base_url")
}

/**
 * Build OmniMind-managed config.toml.
 *
 * Managed keys are rewritten; [features] is merged so unrelated feature flags
 * (auto_compaction/hooks/goals/...) survive. fast_mode is always written as a
 * boolean — never "deleted to mean off". auto_compaction is written only when
 * the caller provides an explicit value (or an existing value is preserved).
 * web_search is written only when [webSearchMode] normalizes to a known mode
 * (S-Default-A: null omits so Codex defaults to Cached). Callers that need
 * preserve must resolve requested ?: existing before passing.
 */
internal fun buildCodexConfigToml(
    baseUrl: String,
    model: String,
    serviceTier: String? = null,
    modelReasoningEffort: String = "",
    defaultGoal: String = "",
    fastMode: Boolean = false,
    autoCompaction: Boolean? = null,
    contextTokenThreshold: Int? = null,
    webSearchMode: String? = null,
    existingFeatures: Map<String, String> = emptyMap(),
    existingToml: String = ""
): String {
    val lines = mutableListOf(
        "model_provider = \"$CODEX_INTERNAL_MODEL_PROVIDER\"",
        "model = ${tomlString(model)}",
        "disable_response_storage = true"
    )
    val normalizedEffort = normalizeCodexReasoningEffort(modelReasoningEffort)
    if (!normalizedEffort.isNullOrBlank()) {
        lines += "model_reasoning_effort = ${tomlString(normalizedEffort)}"
    }
    // service_tier is independent of features.fast_mode; off/false/default omit it.
    val normalizedServiceTier = normalizeCodexServiceTier(serviceTier)
    if (fastMode) {
        // When Fast is on, prefer an explicit fast tier when none/other not set.
        val tierToWrite = normalizedServiceTier ?: "fast"
        if (tierToWrite.isNotBlank()) {
            lines += "service_tier = ${tomlString(tierToWrite)}"
        }
    } else if (!normalizedServiceTier.isNullOrBlank() && normalizedServiceTier != "fast") {
        lines += "service_tier = ${tomlString(normalizedServiceTier)}"
    }
    if (defaultGoal.isNotBlank()) {
        // Soft OmniMind preference used by the app; ignored by stock Codex.
        lines += "omnimind_default_goal = ${tomlString(defaultGoal)}"
    }
    // B30: soft OmniMind context threshold for the app top bar; stock Codex ignores it.
    if (contextTokenThreshold != null) {
        lines += "omnimind_context_token_threshold = ${clampContextTokenThreshold(contextTokenThreshold)}"
    }
    // P0/P1: top-level web_search; omit when null (Codex Cached default).
    val normalizedWebSearch = normalizeCodexWebSearchMode(webSearchMode)
    if (normalizedWebSearch != null) {
        lines += "web_search = ${tomlString(normalizedWebSearch)}"
    }
    // Preserve unmanaged top-level scalar keys from the previous config so a
    // local write does not silently drop approvals_reviewer / sandbox_mode / etc.
    val preservedTopLevel = extractPreservedTopLevelTomlLines(existingToml)
    if (preservedTopLevel.isNotEmpty()) {
        lines += preservedTopLevel
    }
    lines += ""
    lines += buildCodexFeaturesTomlSection(
        fastMode = fastMode,
        autoCompaction = autoCompaction,
        existingFeatures = existingFeatures,
    )
    lines += listOf(
        "",
        "[model_providers.$CODEX_INTERNAL_MODEL_PROVIDER]",
        "name = \"$CODEX_INTERNAL_MODEL_PROVIDER\"",
        "base_url = ${tomlString(baseUrl)}",
        "wire_api = \"responses\"",
        "requires_openai_auth = true"
    )
    val otherTables = extractPreservedTomlTables(
        existingToml,
        skipTables = setOf(
            "features",
            "model_providers.$CODEX_INTERNAL_MODEL_PROVIDER",
        )
    )
    if (otherTables.isNotEmpty()) {
        lines += ""
        lines += otherTables
    }
    return lines.joinToString(separator = "\n", postfix = "\n")
}

/**
 * Resolve the boolean features.fast_mode value for a write.
 *
 * Priority: explicit fastMode/fast_mode arg → serviceTier fast/off when provided →
 * existing config → default false. Never treat "missing key" as the write target.
 */
internal fun resolveCodexFastMode(
    requestedFastMode: Boolean?,
    serviceTier: String?,
    serviceTierArgPresent: Boolean,
    existingFastMode: Boolean?
): Boolean {
    if (requestedFastMode != null) {
        return requestedFastMode
    }
    val normalizedTier = normalizeCodexServiceTier(serviceTier)
    if (serviceTierArgPresent) {
        return normalizedTier == "fast"
    }
    return existingFastMode ?: false
}

/**
 * Emit a [features] table that always includes fast_mode = true|false and
 * preserves other known feature keys from the previous config body.
 *
 * When [autoCompaction] is non-null, force-write `auto_compaction = true|false`
 * without wiping hooks/goals/other features. When null, keep any existing value.
 */
internal fun buildCodexFeaturesTomlSection(
    fastMode: Boolean,
    autoCompaction: Boolean? = null,
    existingFeatures: Map<String, String> = emptyMap()
): List<String> {
    val merged = linkedMapOf<String, String>()
    existingFeatures.forEach { (key, value) ->
        val normalizedKey = key.trim()
        if (normalizedKey.isEmpty() ||
            normalizedKey.equals("fast_mode", ignoreCase = true) ||
            (autoCompaction != null &&
                normalizedKey.equals("auto_compaction", ignoreCase = true))
        ) {
            return@forEach
        }
        merged[normalizedKey] = value.trim()
    }
    // Always write an explicit boolean. Deleting the key is not allowed for "off".
    merged["fast_mode"] = if (fastMode) "true" else "false"
    if (autoCompaction != null) {
        merged["auto_compaction"] = if (autoCompaction) "true" else "false"
    }
    val lines = mutableListOf("[features]")
    // Stable-ish order: preserve discovery order of existing keys, then fast_mode last
    // if it was not present; but since we force-set fast_mode after copy, put common
    // keys first for readability.
    val preferredOrder = listOf("auto_compaction", "hooks", "goals", "fast_mode")
    val emitted = linkedSetOf<String>()
    for (key in preferredOrder) {
        val value = merged[key] ?: continue
        lines += "$key = $value"
        emitted += key
    }
    for ((key, value) in merged) {
        if (key in emitted) continue
        lines += "$key = $value"
    }
    return lines
}

internal fun normalizeCodexServiceTier(raw: String?): String? {
    val normalized = raw?.trim()?.lowercase().orEmpty()
    if (normalized.isEmpty() || normalized == "default" || normalized == "off" || normalized == "false") {
        return null
    }
    return when (normalized) {
        "fast", "priority", "true", "1", "on" -> "fast"
        else -> normalized
    }
}

/** Normalize product web_search mode. Returns null for blank/unknown. */
internal fun normalizeCodexWebSearchMode(raw: String?): String? {
    val n = raw?.trim()?.lowercase().orEmpty()
    if (n.isEmpty() || n == "default" || n == "auto") return null
    return when (n) {
        "cached", "cache" -> "cached"
        "live", "live_internet", "request" -> "live"
        "disabled", "off", "false", "none" -> "disabled"
        "indexed", "index" -> "indexed" // allow pass-through
        else -> null
    }
}

/**
 * B26: allow catalog tokens including max/ultra when writing config.toml.
 * Alias-only normalization; unknown garbage still drops to null.
 */
private fun normalizeCodexReasoningEffort(raw: String?): String? {
    val normalized = raw?.trim()?.lowercase().orEmpty()
    if (normalized.isEmpty()) {
        return null
    }
    return when (normalized) {
        "no", "none", "off" -> "none"
        "min", "minimal", "minimum" -> "minimal"
        "low" -> "low"
        "med", "medium" -> "medium"
        "high" -> "high"
        "extra_high", "extra-high", "very_high", "very-high", "x-high", "x high", "xhigh" -> "xhigh"
        "max", "maximum" -> "max"
        "ultra" -> "ultra"
        // Pass through other catalog-shaped tokens so model/list efforts survive TOML write.
        else -> if (normalized.matches(Regex("^[a-z0-9][a-z0-9_-]{0,31}$"))) {
            normalized
        } else {
            null
        }
    }
}

private fun extractMarkedBlock(source: String, startMarker: String, endMarker: String): String {
    val start = source.indexOf(startMarker)
    if (start < 0) return ""
    val bodyStart = start + startMarker.length
    val end = source.indexOf(endMarker, bodyStart)
    if (end < 0) return ""
    return source.substring(bodyStart, end).trim()
}

private fun extractTomlString(source: String, key: String): String? {
    if (source.isBlank()) return null
    val escapedKey = Regex.escape(key)
    val pattern = Regex(
        pattern = """(?m)^\s*$escapedKey\s*=\s*"((?:\\.|[^"\\])*)"\s*(?:#.*)?$"""
    )
    return pattern.find(source)?.groupValues?.getOrNull(1)?.let(::unescapeTomlBasicString)
}

/**
 * Parse an unquoted or quoted TOML boolean for [key]. Returns null when absent
 * or not a boolean-like value.
 */
internal fun extractTomlBoolean(source: String, key: String): Boolean? {
    if (source.isBlank()) return null
    val escapedKey = Regex.escape(key)
    val pattern = Regex(
        pattern = """(?m)^\s*$escapedKey\s*=\s*("?)(true|false)\1\s*(?:#.*)?$""",
        option = RegexOption.IGNORE_CASE
    )
    val raw = pattern.find(source)?.groupValues?.getOrNull(2)?.lowercase() ?: return null
    return raw == "true"
}

/**
 * Parse an integer TOML scalar for [key] (bare or quoted). Returns null when
 * absent or not an integer.
 */
internal fun extractTomlInt(source: String, key: String): Int? {
    if (source.isBlank()) return null
    val escapedKey = Regex.escape(key)
    val pattern = Regex(
        pattern = """(?m)^\s*$escapedKey\s*=\s*"?(-?\d+)"?\s*(?:#.*)?$"""
    )
    val raw = pattern.find(source)?.groupValues?.getOrNull(1) ?: return null
    return raw.toIntOrNull()
}

/** Clamp app-managed context token threshold to a sane write range. */
internal fun clampContextTokenThreshold(value: Int): Int {
    return value.coerceIn(10_000, 1_000_000)
}

/**
 * Return the body of a top-level `[table]` section until the next table header.
 * Nested tables like `[features.foo]` are not treated as part of `[features]`.
 */
internal fun extractTomlTableBody(source: String, table: String): String {
    if (source.isBlank()) return ""
    val escaped = Regex.escape(table)
    val header = Regex("""(?m)^\s*\[$escaped]\s*(?:#.*)?$""")
    val match = header.find(source) ?: return ""
    val bodyStart = match.range.last + 1
    val rest = source.substring(bodyStart)
    val nextHeader = Regex("""(?m)^\s*\[[^\]]+]\s*(?:#.*)?$""").find(rest)
    val body = if (nextHeader == null) rest else rest.substring(0, nextHeader.range.first)
    return body.trim()
}

/**
 * Collect simple key = value pairs inside a TOML table body. Values keep their
 * original text (quotes / bare tokens) so they can be re-emitted.
 */
internal fun extractTomlTableEntries(source: String, table: String): Map<String, String> {
    val body = extractTomlTableBody(source, table)
    if (body.isBlank()) return emptyMap()
    val entries = linkedMapOf<String, String>()
    val linePattern = Regex(
        pattern = """(?m)^\s*([A-Za-z0-9_.-]+)\s*=\s*(.+?)\s*(?:#.*)?$"""
    )
    for (match in linePattern.findAll(body)) {
        val key = match.groupValues.getOrNull(1)?.trim().orEmpty()
        val value = match.groupValues.getOrNull(2)?.trim().orEmpty()
        if (key.isEmpty() || value.isEmpty()) continue
        // Skip nested array/table starters; keep scalars (bool/string/number).
        if (value.startsWith("[") || value.startsWith("{")) continue
        entries[key] = value
    }
    return entries
}

/** Top-level keys rewritten by [buildCodexConfigToml]; anything else may be preserved. */
private val CODEX_MANAGED_TOP_LEVEL_KEYS = setOf(
    "model_provider",
    "model",
    "disable_response_storage",
    "model_reasoning_effort",
    "service_tier",
    "omnimind_default_goal",
    "omnimind_context_token_threshold",
    "web_search",
    "fast_mode"
)

/**
 * Keep unmanaged top-level scalar assignments from an existing config so a
 * rewrite does not drop operator-set keys (approval_policy, sandbox_mode, ...).
 */
internal fun extractPreservedTopLevelTomlLines(source: String): List<String> {
    if (source.isBlank()) return emptyList()
    val firstTable = Regex("""(?m)^\s*\[[^\]]+]\s*(?:#.*)?$""").find(source)
    val preamble = if (firstTable == null) source else source.substring(0, firstTable.range.first)
    val lines = mutableListOf<String>()
    val assignment = Regex("""^\s*([A-Za-z0-9_.-]+)\s*=\s*(.+?)\s*(?:#.*)?$""")
    for (rawLine in preamble.lines()) {
        val match = assignment.find(rawLine) ?: continue
        val key = match.groupValues[1].trim()
        if (key in CODEX_MANAGED_TOP_LEVEL_KEYS) continue
        val value = match.groupValues[2].trim()
        if (value.startsWith("[") || value.startsWith("{")) continue
        lines += "$key = $value"
    }
    return lines
}

/**
 * Re-emit whole TOML tables other than the managed ones. Nested tables that
 * start with a skipped prefix (e.g. model_providers.omnimind.auth) are also
 * skipped so the managed provider block stays authoritative.
 */
internal fun extractPreservedTomlTables(
    source: String,
    skipTables: Set<String>
): List<String> {
    if (source.isBlank()) return emptyList()
    val headerPattern = Regex("""(?m)^\s*\[([^\]]+)]\s*(?:#.*)?$""")
    val matches = headerPattern.findAll(source).toList()
    if (matches.isEmpty()) return emptyList()
    val blocks = mutableListOf<String>()
    for (index in matches.indices) {
        val match = matches[index]
        val tableName = match.groupValues[1].trim()
        if (shouldSkipTomlTable(tableName, skipTables)) continue
        val start = match.range.first
        val end = if (index + 1 < matches.size) {
            matches[index + 1].range.first
        } else {
            source.length
        }
        val block = source.substring(start, end).trimEnd()
        if (block.isNotBlank()) {
            blocks += block.trim()
        }
    }
    return blocks
}

private fun shouldSkipTomlTable(tableName: String, skipTables: Set<String>): Boolean {
    val normalized = tableName.trim()
    if (normalized in skipTables) return true
    // Skip nested tables under a managed parent (model_providers.omnimind.*).
    return skipTables.any { skip ->
        normalized == skip || normalized.startsWith("$skip.")
    }
}

private fun extractOpenAiApiKey(source: String): String? {
    val trimmed = source.trim()
    if (trimmed.isEmpty()) return null
    return runCatching {
        JSONObject(trimmed).optString("OPENAI_API_KEY").trim().takeIf { it.isNotEmpty() }
    }.getOrNull()
}

private fun tomlString(value: String): String {
    return buildString {
        append('"')
        value.forEach { char ->
            when (char) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\t' -> append("\\t")
                '\n' -> append("\\n")
                '\u000C' -> append("\\f")
                '\r' -> append("\\r")
                else -> {
                    if (char.code < 0x20) {
                        append("\\u")
                        append(char.code.toString(16).padStart(4, '0'))
                    } else {
                        append(char)
                    }
                }
            }
        }
        append('"')
    }
}

private fun unescapeTomlBasicString(value: String): String {
    val result = StringBuilder(value.length)
    var index = 0
    while (index < value.length) {
        val char = value[index]
        if (char != '\\' || index == value.lastIndex) {
            result.append(char)
            index += 1
            continue
        }
        val escaped = value[index + 1]
        when (escaped) {
            'b' -> result.append('\b')
            't' -> result.append('\t')
            'n' -> result.append('\n')
            'f' -> result.append('\u000C')
            'r' -> result.append('\r')
            '"' -> result.append('"')
            '\\' -> result.append('\\')
            else -> result.append(escaped)
        }
        index += 2
    }
    return result.toString()
}

private fun shellQuote(value: String): String {
    return "'" + value.replace("'", "'\"'\"'") + "'"
}

private fun Map<String, Any?>.stringValue(key: String): String? {
    return this[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
}

/**
 * Coerce a map value into a Boolean when the caller intended a boolean flag.
 * Accepts Boolean, Number (non-zero), and common string forms (true/false/1/0/on/off).
 * Returns null when the key is absent or not boolean-like.
 */
private fun Map<String, Any?>.booleanValue(key: String): Boolean? {
    if (!containsKey(key)) return null
    val raw = this[key] ?: return null
    return when (raw) {
        is Boolean -> raw
        is Number -> raw.toInt() != 0
        is String -> {
            when (raw.trim().lowercase()) {
                "true", "1", "on", "yes" -> true
                "false", "0", "off", "no" -> false
                else -> null
            }
        }
        else -> null
    }
}

private fun Map<String, Any?>.longValue(key: String): Long? {
    val raw = this[key] ?: return null
    return when (raw) {
        is Number -> raw.toLong()
        is String -> raw.trim().toLongOrNull()
        else -> null
    }
}

private fun Map<String, Any?>.intValue(key: String): Int? {
    val raw = this[key] ?: return null
    return when (raw) {
        is Number -> raw.toInt()
        is String -> raw.trim().toIntOrNull()
        else -> null
    }
}

private fun Map<String, Any?>.mapValue(key: String): Map<String, Any?> {
    val raw = this[key] as? Map<*, *> ?: return emptyMap()
    return raw.entries.associate { (entryKey, value) -> entryKey.toString() to value }
}

private val CODEX_ENVELOPE_KEYS = listOf(
    "message",
    "payload",
    "data",
    "event",
    "notification",
    "params",
    "result",
    "_meta",
    "msg"
)

private fun extractCodexServerMethod(value: Any?, depth: Int = 0): String {
    val map = value as? Map<*, *> ?: return ""
    if (depth > 6) {
        return ""
    }
    val direct = normalizeCodexServerMethod(map["method"]?.toString()?.trim())
    if (direct.isNotBlank()) {
        return direct
    }
    for (key in CODEX_ENVELOPE_KEYS) {
        val nested = extractCodexServerMethod(map[key], depth + 1)
        if (nested.isNotBlank()) {
            return nested
        }
    }
    val rawType = map["type"]?.toString()?.trim()
    if (codexServerTypeLooksLikeMethod(rawType)) {
        return normalizeCodexServerMethod(rawType)
    }
    return ""
}

private fun codexServerTypeLooksLikeMethod(rawType: String?): Boolean {
    val type = rawType?.trim().orEmpty()
    if (type.isBlank()) {
        return false
    }
    val normalized = normalizeCodexServerMethod(type)
    return normalized.contains("/") ||
        normalized == "error" ||
        type in CODEX_THREAD_ITEM_TYPES
}

private fun extractCodexServerParams(value: Any?, depth: Int = 0): Map<String, Any?> {
    val map = value as? Map<*, *> ?: return emptyMap()
    if (depth > 6) {
        return emptyMap()
    }
    val direct = map["params"] as? Map<*, *>
    if (direct != null) {
        val nested = extractCodexServerParams(direct, depth + 1)
        if (nested.isNotEmpty()) {
            return topLevelCodexIds(map) + nested
        }
        val normalized = direct.entries.associate { (entryKey, nestedValue) ->
            entryKey.toString() to nestedValue
        }
        if (normalized.isNotEmpty()) {
            return topLevelCodexIds(map) + normalized
        }
    }
    for (key in CODEX_ENVELOPE_KEYS) {
        if (key == "params") {
            continue
        }
        val nested = extractCodexServerParams(map[key], depth + 1)
        if (nested.isNotEmpty()) {
            return topLevelCodexIds(map) + nested
        }
    }
    return emptyMap()
}

private fun topLevelCodexIds(map: Map<*, *>): Map<String, Any?> {
    val ids = linkedMapOf<String, Any?>()
    val meta = map["_meta"] as? Map<*, *>
    if (meta != null) {
        for (key in listOf("threadId", "thread_id")) {
            if (meta.containsKey(key)) {
                ids[key] = meta[key]
            }
        }
    }
    for (key in listOf("threadId", "thread_id", "turnId", "turn_id", "itemId", "item_id")) {
        if (map.containsKey(key)) {
            ids[key] = map[key]
        }
    }
    return ids
}

private fun normalizeCodexServerMethod(rawMethod: String?): String {
    val method = rawMethod?.trim().orEmpty()
    if (method.isEmpty()) {
        return ""
    }
    return when (method) {
        "thread.started" -> "thread/started"
        "turn.started" -> "turn/started"
        "turn.completed" -> "turn/completed"
        "turn.failed" -> "turn/failed"
        "item.started" -> "item/started"
        "item.updated" -> "item/updated"
        "item.completed" -> "item/completed"
        else -> method
            .replace("/agent_message/", "/agentMessage/")
            .replace("/command_execution/", "/commandExecution/")
            .replace("/file_change/", "/fileChange/")
            .replace("/mcp_tool_call/", "/mcpToolCall/")
    }
}

private fun syntheticCodexServerParams(
    message: Map<String, Any?>,
    method: String
): Map<String, Any?> {
    if (method.isBlank()) {
        return emptyMap()
    }
    val payload = linkedMapOf<String, Any?>()
    message.forEach { (key, value) ->
        if (key != "method" && key != "type" && key != "params") {
            payload[key] = value
        }
    }
    return payload
}

private fun codexProtocolEventType(value: Any?): String {
    val msg = codexProtocolMsg(value) ?: return ""
    return msg["type"]?.toString()?.trim()?.lowercase()
        ?.replace(Regex("[^a-z0-9]+"), "_")
        .orEmpty()
}

private fun codexProtocolMsg(value: Any?, depth: Int = 0): Map<*, *>? {
    val map = value as? Map<*, *> ?: return null
    if (depth > 6) {
        return null
    }
    val direct = map["msg"] as? Map<*, *>
    if (direct != null) {
        return direct
    }
    for (key in CODEX_ENVELOPE_KEYS) {
        val nested = codexProtocolMsg(map[key], depth + 1)
        if (nested != null) {
            return nested
        }
    }
    return null
}

private fun extractThreadId(value: Any?): String? {
    return extractStringRecursive(
        value = value,
        keys = setOf("threadId", "thread_id"),
        nestedObjectKeys = setOf(
            "thread",
            "message",
            "payload",
            "data",
            "event",
            "notification",
            "params",
            "result",
            "_meta",
            "msg"
        )
    )
}

private fun extractTurnId(value: Any?): String? {
    val fromTurn = extractStringRecursive(
        value = value,
        keys = setOf("turnId", "turn_id"),
        nestedObjectKeys = setOf(
            "turn",
            "message",
            "payload",
            "data",
            "event",
            "notification",
            "params",
            "result",
            "_meta",
            "msg"
        )
    )
    if (!fromTurn.isNullOrBlank()) {
        return fromTurn
    }
    val map = value as? Map<*, *> ?: return null
    val turn = map["turn"] as? Map<*, *> ?: return null
    return turn["id"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
}

private fun extractActiveTurnId(value: Any?): String? {
    val direct = extractStringRecursive(
        value = value,
        keys = setOf(
            "turnId",
            "turn_id",
            "activeTurnId",
            "active_turn_id",
            "currentTurnId",
            "current_turn_id"
        ),
        nestedObjectKeys = setOf(
            "thread",
            "turn",
            "status",
            "message",
            "payload",
            "data",
            "event",
            "notification",
            "params",
            "result",
            "_meta",
            "msg"
        )
    )
    if (!direct.isNullOrBlank()) {
        return direct
    }
    val root = value as? Map<*, *> ?: return null
    val thread = root["thread"] as? Map<*, *>
    val turns = (thread?.get("turns") as? List<*>) ?: (root["turns"] as? List<*>) ?: return null
    for (index in turns.indices.reversed()) {
        val turn = turns[index] as? Map<*, *> ?: continue
        val active = codexActivityFromValue(turn["status"] ?: turn["state"])
        if (active == true) {
            return turn["id"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        }
    }
    return null
}

private fun codexThreadActivity(value: Any?): Boolean? {
    val root = value as? Map<*, *> ?: return null
    val thread = root["thread"] as? Map<*, *>
    var inactiveCandidate: Boolean? = null
    val candidates = listOf(
        root["active"],
        root["isActive"],
        root["is_active"],
        root["status"],
        root["state"],
        root["turnStatus"],
        root["turn_status"],
        thread?.get("active"),
        thread?.get("isActive"),
        thread?.get("is_active"),
        thread?.get("status"),
        thread?.get("state"),
        thread?.get("turnStatus"),
        thread?.get("turn_status")
    )
    for (candidate in candidates) {
        val active = codexActivityFromValue(candidate)
        if (active == true) {
            return true
        }
        if (active == false) {
            inactiveCandidate = false
        }
    }
    for (key in CODEX_ENVELOPE_KEYS) {
        val nested = root[key] as? Map<*, *> ?: continue
        val nestedActivity = codexThreadActivity(nested)
        if (nestedActivity == true) {
            return true
        }
        if (nestedActivity == false) {
            inactiveCandidate = false
        }
    }
    val turns = (thread?.get("turns") as? List<*>) ?: (root["turns"] as? List<*>)
    if (turns != null) {
        for (index in turns.indices.reversed()) {
            val turn = turns[index] as? Map<*, *> ?: continue
            val active = codexActivityFromValue(turn["status"] ?: turn["state"])
            if (active != null) {
                return active
            }
        }
    }
    return inactiveCandidate
}

private fun codexActivityFromValue(value: Any?): Boolean? {
    if (value is Boolean) {
        return value
    }
    val text = codexStatusText(value)?.lowercase()
        ?.replace(Regex("[^a-z0-9]+"), "")
        ?: return null
    return when (text) {
        "running", "active", "busy", "inprogress", "inflight", "executing" -> true
        "idle", "closed", "completed", "complete", "notloaded", "systemerror",
        "failed", "cancelled", "canceled", "interrupted" -> false
        else -> null
    }
}

private fun codexStatusText(value: Any?): String? {
    return when (value) {
        null -> null
        is String -> value.trim().takeIf { it.isNotEmpty() }
        is Number, is Boolean -> value.toString()
        is Map<*, *> -> {
            listOf("type", "status", "state", "value", "name")
                .firstNotNullOfOrNull { key -> codexStatusText(value[key]) }
        }
        else -> null
    }
}

private fun extractThreadTitle(value: Any?): String? {
    val map = value as? Map<*, *> ?: return null
    val params = map["params"] as? Map<*, *>
    val result = map["result"] as? Map<*, *>
    val thread = map["thread"] as? Map<*, *>
    return listOfNotNull(
        map["threadName"],
        map["thread_name"],
        map["name"],
        map["title"],
        map["preview"],
        params?.get("threadName"),
        params?.get("thread_name"),
        params?.get("name"),
        params?.get("title"),
        params?.get("preview"),
        result?.get("threadName"),
        result?.get("thread_name"),
        result?.get("name"),
        result?.get("title"),
        result?.get("preview"),
        thread?.get("name"),
        thread?.get("title"),
        thread?.get("preview"),
        (params?.get("thread") as? Map<*, *>)?.get("name"),
        (result?.get("thread") as? Map<*, *>)?.get("name"),
        (params?.get("thread") as? Map<*, *>)?.get("title"),
        (result?.get("thread") as? Map<*, *>)?.get("title"),
        (params?.get("thread") as? Map<*, *>)?.get("preview"),
        (result?.get("thread") as? Map<*, *>)?.get("preview")
    ).firstNotNullOfOrNull { it?.toString()?.trim()?.takeIf(String::isNotEmpty) }
}

private fun extractStringRecursive(
    value: Any?,
    keys: Set<String>,
    nestedObjectKeys: Set<String>
): String? {
    val map = value as? Map<*, *> ?: return null
    for (key in keys) {
        val direct = map[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        if (direct != null) {
            return direct
        }
    }
    for (nestedKey in nestedObjectKeys) {
        val nested = map[nestedKey] as? Map<*, *>
        if (nestedKey == "thread" || nestedKey == "turn") {
            val id = nested?.get("id")?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            if (id != null) {
                return id
            }
        }
        val recursive = extractStringRecursive(nested, keys, nestedObjectKeys)
        if (recursive != null) {
            return recursive
        }
    }
    val params = map["params"] as? Map<*, *>
    val fromParams = extractStringRecursive(params, keys, nestedObjectKeys)
    if (fromParams != null) {
        return fromParams
    }
    val result = map["result"] as? Map<*, *>
    return extractStringRecursive(result, keys, nestedObjectKeys)
}

private fun collectThreadEntries(value: Any?): List<CodexThreadListEntry> {
    val entries = mutableListOf<CodexThreadListEntry>()
    fun visit(current: Any?, parentKey: String? = null) {
        when (current) {
            is List<*> -> current.forEach { visit(it, parentKey) }
            is Map<*, *> -> {
                val threadMap = current["thread"] as? Map<*, *>
                val threadId = threadEntryId(current, threadMap, parentKey)
                if (threadId != null) {
                    val cwd = listOfNotNull(current["cwd"], threadMap?.get("cwd"))
                        .firstNotNullOfOrNull {
                            it?.toString()?.trim()?.takeIf(String::isNotEmpty)
                        }
                    val title = listOfNotNull(
                        current["name"],
                        current["title"],
                        current["preview"],
                        current["threadName"],
                        current["thread_name"],
                        threadMap?.get("name"),
                        threadMap?.get("title"),
                        threadMap?.get("preview")
                    ).firstNotNullOfOrNull {
                        it?.toString()?.trim()?.takeIf(String::isNotEmpty)
                    }
                    val archived = listOfNotNull(
                        current["archived"],
                        current["isArchived"],
                        current["is_archived"],
                        threadMap?.get("archived"),
                        threadMap?.get("isArchived"),
                        threadMap?.get("is_archived")
                    ).firstNotNullOfOrNull(::asBooleanOrNull)
                    entries += CodexThreadListEntry(
                        threadId = threadId,
                        cwd = cwd,
                        title = title,
                        archived = archived
                    )
                }
                current.entries.forEach { (key, nestedValue) ->
                    val nestedKey = key?.toString()
                    if (nestedKey !in THREAD_ITEM_COLLECTION_KEYS) {
                        visit(nestedValue, nestedKey)
                    }
                }
            }
        }
    }
    visit(value)
    return entries.distinctBy { it.threadId }
}

private fun threadEntryId(
    current: Map<*, *>,
    threadMap: Map<*, *>?,
    parentKey: String?
): String? {
    return listOfNotNull(
        current["threadId"],
        current["thread_id"],
        threadMap?.get("id"),
        if (current.looksLikeThreadEntry(threadMap, parentKey)) current["id"] else null
    ).firstNotNullOfOrNull {
        it?.toString()?.trim()?.takeIf(String::isNotEmpty)
    }
}

private fun Map<*, *>.looksLikeThreadEntry(threadMap: Map<*, *>?, parentKey: String?): Boolean {
    if (threadMap != null || containsKey("threadId") || containsKey("thread_id")) {
        return true
    }
    if (!containsKey("id")) {
        return false
    }
    val normalizedParentKey = parentKey?.lowercase().orEmpty()
    if (normalizedParentKey == "thread" || normalizedParentKey == "threads") {
        return true
    }
    val type = this["type"]?.toString()?.trim().orEmpty()
    if (type in CODEX_THREAD_ITEM_TYPES) {
        return false
    }
    return keys.any { key ->
        key?.toString() in THREAD_SUMMARY_KEYS
    }
}

private fun asBooleanOrNull(value: Any?): Boolean? {
    return when (value) {
        is Boolean -> value
        is Number -> value.toInt() != 0
        is String -> when (value.trim().lowercase()) {
            "true", "1", "yes" -> true
            "false", "0", "no" -> false
            else -> null
        }
        else -> null
    }
}

internal fun resolveCodexReviewTarget(value: Any?): Map<String, Any?> {
    val target = value as? Map<*, *>
    if (target.isNullOrEmpty()) {
        return mapOf("type" to "uncommittedChanges")
    }
    return target.entries.mapNotNull { (key, nestedValue) ->
        val normalizedKey = key?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: return@mapNotNull null
        normalizedKey to nestedValue
    }.toMap().ifEmpty { mapOf("type" to "uncommittedChanges") }
}

private val THREAD_ITEM_COLLECTION_KEYS = setOf(
    "items",
    "inputItems",
    "input_items",
    "outputItems",
    "output_items",
    "responseItems",
    "response_items",
    "rawItems",
    "raw_items",
    "events",
    "messages",
    "turns"
)

private val THREAD_SUMMARY_KEYS = setOf(
    "cwd",
    "name",
    "title",
    "preview",
    "threadName",
    "thread_name",
    "archived",
    "isArchived",
    "is_archived",
    "sourceKind",
    "source_kind",
    "createdAt",
    "created_at",
    "updatedAt",
    "updated_at",
    "lastActivityAt",
    "last_activity_at"
)

private val CODEX_THREAD_ITEM_TYPES = setOf(
    "agentMessage",
    "agent_message",
    "reasoning",
    "commandExecution",
    "command_execution",
    "local_shell_call",
    "commandExec",
    "processExecution",
    "fileChange",
    "file_change",
    "tool",
    "mcpToolCall",
    "mcp_tool_call",
    "dynamicToolCall",
    "dynamic_tool_call",
    "function_call",
    "function_call_output",
    "custom_tool_call",
    "custom_tool_call_output",
    "tool_search_call",
    "tool_search_output",
    "webSearch",
    "web_search",
    "web_search_call",
    "imageView",
    "image_view",
    "imageGeneration",
    "image_generation",
    "image_generation_call",
    "collabAgentToolCall",
    "collab_agent_tool_call",
    "collabToolCall",
    "collab_tool_call",
    "userMessage",
    "user_message",
    "todo_list",
    "plan",
    "serverRequest"
)

internal val DEFAULT_CODEX_THREAD_SOURCE_KINDS = listOf(
    "cli",
    "vscode",
    "exec",
    "appServer",
    "subAgent",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther"
)
