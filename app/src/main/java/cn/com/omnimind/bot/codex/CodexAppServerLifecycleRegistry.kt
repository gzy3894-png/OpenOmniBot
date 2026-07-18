package cn.com.omnimind.bot.codex

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap

/**
 * Orders session-owned message effects against explicit session transitions.
 *
 * A server message may suspend while synchronizing its thread binding. Session
 * replacement must wait for that work to finish; once replacement commits,
 * later messages from the old session fail the generation/identity check.
 */
internal class CodexServerMessageBarrier {
    private val mutex = Mutex()

    suspend fun <T> run(action: suspend () -> T): T {
        return mutex.withLock { action() }
    }
}

/**
 * Returns a positive generation that remains monotonic when the wall clock
 * moves backwards. The caller persists the returned value before publishing
 * the corresponding session.
 */
internal fun nextCodexSessionGeneration(
    previousPersisted: Long,
    nowMillis: Long,
): Long {
    val previous = previousPersisted.coerceAtLeast(0L)
    check(previous < Long.MAX_VALUE) {
        "Codex session generation counter is exhausted."
    }
    return maxOf(previous + 1L, nowMillis.coerceAtLeast(1L))
}

internal enum class CodexSessionReadiness {
    DISCONNECTED,
    STARTING,
    READY,
}

internal fun isCodexSessionReadyForUse(
    readiness: CodexSessionReadiness,
    transportRunning: Boolean,
    runtimeMatches: Boolean,
): Boolean {
    return readiness == CodexSessionReadiness.READY &&
        transportRunning &&
        runtimeMatches
}

internal data class CodexEventListenerRegistration(
    val engineToken: String,
    val streamToken: String,
    val listener: (Map<String, Any?>) -> Unit,
) {
    private val deliveredPendingRequestKeys =
        ConcurrentHashMap.newKeySet<String>()

    fun claimPendingRequestDelivery(deliveryKey: String): Boolean {
        return deliveredPendingRequestKeys.add(deliveryKey)
    }

    fun releasePendingRequestDelivery(deliveryKey: String) {
        deliveredPendingRequestKeys.remove(deliveryKey)
    }

    fun pendingRequestDeliveryCount(): Int {
        return deliveredPendingRequestKeys.size
    }
}

/**
 * Process-wide listener registry shared by every FlutterEngine.
 *
 * Registrations are owned by a stream token, so cancelling one EventChannel
 * subscription cannot clear listeners that belong to another engine.
 */
internal class CodexEventListenerRegistry {
    private val registrations =
        ConcurrentHashMap<String, CodexEventListenerRegistration>()

    fun register(
        engineToken: String,
        streamToken: String,
        listener: (Map<String, Any?>) -> Unit,
    ): CodexEventListenerRegistration {
        val registration = CodexEventListenerRegistration(
            engineToken = engineToken,
            streamToken = streamToken,
            listener = listener,
        )
        registrations[streamToken] = registration
        return registration
    }

    fun unregister(streamToken: String): CodexEventListenerRegistration? {
        return registrations.remove(streamToken)
    }

    fun snapshot(): List<CodexEventListenerRegistration> {
        return registrations.values.sortedBy { it.streamToken }
    }

    /**
     * The pending delivery key is claimed at the actual listener invocation
     * boundary. This collapses a queued live event and registration replay for
     * one stream without suppressing resolved/invalidated terminal events,
     * which intentionally carry no pending delivery key.
     */
    fun deliver(
        registration: CodexEventListenerRegistration,
        event: Map<String, Any?>,
        pendingDeliveryPreclaimed: Boolean = false,
    ): Boolean {
        val deliveryKey = event["serverRequestDeliveryKey"]
            ?.toString()
            ?.takeIf { it.isNotBlank() }
        if (registrations[registration.streamToken] !== registration) {
            if (pendingDeliveryPreclaimed && deliveryKey != null) {
                registration.releasePendingRequestDelivery(deliveryKey)
            }
            return false
        }
        val terminalRequestKey = event["serverRequestKey"]
            ?.toString()
            ?.takeIf {
                it.isNotBlank() &&
                    deliveryKey == null &&
                    (event["method"] == "serverRequest/resolved" ||
                        event["method"] == "serverRequest/invalidated")
            }
        if (deliveryKey != null &&
            !pendingDeliveryPreclaimed &&
            !registration.claimPendingRequestDelivery(deliveryKey)
        ) {
            return false
        }
        try {
            registration.listener(event)
            return true
        } catch (error: Throwable) {
            if (deliveryKey != null) {
                registration.releasePendingRequestDelivery(deliveryKey)
            }
            throw error
        } finally {
            if (terminalRequestKey != null) {
                registration.releasePendingRequestDelivery(
                    codexPendingServerRequestDeliveryKey(terminalRequestKey),
                )
            }
        }
    }

    fun size(): Int = registrations.size
}

internal enum class CodexServerRequestState {
    PENDING,
    RESPONSE_SENDING,
    RESPONSE_SENT,
}

internal data class CodexPendingServerRequest(
    val sessionGeneration: Long,
    val sessionIdentity: Any,
    val requestId: Any,
    val requestKey: String,
    val method: String,
    val threadId: String?,
    val turnId: String?,
    val eventMethod: String,
    val params: Map<String, Any?>,
    val message: Map<String, Any?>,
    val conversationId: Long?,
    val state: CodexServerRequestState,
)

internal data class CodexServerRequestRegistration(
    val request: CodexPendingServerRequest,
    val isNew: Boolean,
)

/**
 * Tracks app-server initiated JSON-RPC requests for exactly one live session
 * generation. All mutating operations are synchronized so responses from two
 * Flutter engines are first-wins.
 */
internal class CodexServerRequestRegistry {
    private val lock = Any()
    private val requests = LinkedHashMap<String, CodexPendingServerRequest>()

    fun register(
        sessionGeneration: Long,
        sessionIdentity: Any,
        requestId: Any,
        method: String,
        threadId: String?,
        turnId: String?,
        eventMethod: String = method,
        params: Map<String, Any?> = emptyMap(),
        message: Map<String, Any?> = emptyMap(),
        conversationId: Long? = null,
    ): CodexServerRequestRegistration = synchronized(lock) {
        val requestKey = codexServerRequestKey(sessionGeneration, requestId)
        val existing = requests[requestKey]
        if (existing != null) {
            return@synchronized CodexServerRequestRegistration(
                request = existing,
                isNew = false,
            )
        }
        val request = CodexPendingServerRequest(
            sessionGeneration = sessionGeneration,
            sessionIdentity = sessionIdentity,
            requestId = requestId,
            requestKey = requestKey,
            method = method,
            threadId = threadId,
            turnId = turnId,
            eventMethod = eventMethod.ifBlank { method },
            params = LinkedHashMap(params),
            message = LinkedHashMap(message),
            conversationId = conversationId,
            state = CodexServerRequestState.PENDING,
        )
        requests[requestKey] = request
        CodexServerRequestRegistration(request = request, isNew = true)
    }

    fun claimForResponse(
        sessionGeneration: Long,
        sessionIdentity: Any,
        requestId: Any,
        expectedMethod: String,
    ): CodexPendingServerRequest = synchronized(lock) {
        val requestKey = codexServerRequestKey(sessionGeneration, requestId)
        val existing = requests[requestKey]
            ?: throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_REQUEST_NOT_PENDING",
                message = "Codex server request is no longer pending.",
            )
        if (existing.sessionIdentity !== sessionIdentity) {
            throw CodexServerRequestResponseException(
                errorCode = "CODEX_STALE_SERVER_REQUEST",
                message = "Codex server request belongs to a stale session.",
            )
        }
        if (existing.method != expectedMethod) {
            throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_REQUEST_METHOD_MISMATCH",
                message = "Codex server request method does not match the pending request.",
            )
        }
        if (existing.state != CodexServerRequestState.PENDING) {
            throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_REQUEST_ALREADY_RESPONDED",
                message = "Codex server request already has a response in progress.",
            )
        }
        existing.copy(state = CodexServerRequestState.RESPONSE_SENDING).also {
            requests[requestKey] = it
        }
    }

    fun markResponseSent(request: CodexPendingServerRequest) = synchronized(lock) {
        val current = requests[request.requestKey] ?: return@synchronized
        if (current.sessionIdentity === request.sessionIdentity &&
            current.state == CodexServerRequestState.RESPONSE_SENDING
        ) {
            requests[request.requestKey] = current.copy(
                state = CodexServerRequestState.RESPONSE_SENT,
            )
        }
    }

    fun restorePendingAfterSendFailure(request: CodexPendingServerRequest) =
        synchronized(lock) {
            val current = requests[request.requestKey] ?: return@synchronized
            if (current.sessionIdentity === request.sessionIdentity &&
                current.state == CodexServerRequestState.RESPONSE_SENDING
            ) {
                requests[request.requestKey] = current.copy(
                    state = CodexServerRequestState.PENDING,
                )
            }
        }

    fun resolve(
        sessionGeneration: Long,
        sessionIdentity: Any,
        requestId: Any,
    ): CodexPendingServerRequest? = synchronized(lock) {
        val requestKey = codexServerRequestKey(sessionGeneration, requestId)
        val current = requests[requestKey] ?: return@synchronized null
        if (current.sessionIdentity !== sessionIdentity) {
            return@synchronized null
        }
        requests.remove(requestKey)
    }

    fun invalidateGeneration(
        sessionGeneration: Long,
        sessionIdentity: Any,
    ): List<CodexPendingServerRequest> = synchronized(lock) {
        val invalidated = requests.values.filter {
            it.sessionGeneration == sessionGeneration &&
                it.sessionIdentity === sessionIdentity
        }
        invalidated.forEach { requests.remove(it.requestKey) }
        invalidated
    }

    fun find(
        sessionGeneration: Long,
        requestId: Any,
    ): CodexPendingServerRequest? = synchronized(lock) {
        requests[codexServerRequestKey(sessionGeneration, requestId)]
    }

    /**
     * Captures only requests that are still actionable for the exact current
     * session. RESPONSE_SENDING/RESPONSE_SENT must never be replayed as a fresh
     * pending card.
     */
    fun snapshotPending(
        sessionGeneration: Long,
        sessionIdentity: Any,
    ): List<CodexPendingServerRequest> = synchronized(lock) {
        requests.values.filter {
            it.sessionGeneration == sessionGeneration &&
                it.sessionIdentity === sessionIdentity &&
                it.state == CodexServerRequestState.PENDING
        }
    }

    /**
     * Revalidates PENDING and claims this stream's delivery key at one linear
     * point with claimForResponse, resolve, and invalidateGeneration. The
     * external EventSink callback runs only after [lock] is released.
     */
    fun claimPendingDelivery(
        request: CodexPendingServerRequest,
        registration: CodexEventListenerRegistration,
    ): Boolean = synchronized(lock) {
        val current = requests[request.requestKey] ?: return@synchronized false
        if (current.sessionIdentity !== request.sessionIdentity ||
            current.method != request.method ||
            current.state != CodexServerRequestState.PENDING
        ) {
            return@synchronized false
        }
        registration.claimPendingRequestDelivery(
            codexPendingServerRequestDeliveryKey(current.requestKey),
        )
    }

    fun size(): Int = synchronized(lock) { requests.size }
}

internal fun buildCodexPendingServerRequestEvent(
    request: CodexPendingServerRequest,
    workspaceId: String,
    replayed: Boolean,
): Map<String, Any?> {
    require(request.state == CodexServerRequestState.PENDING) {
        "Only pending Codex server requests can be delivered as actionable."
    }
    val params = LinkedHashMap(request.params)
    val message = if (request.message.isNotEmpty()) {
        LinkedHashMap(request.message)
    } else {
        linkedMapOf(
            "id" to request.requestId,
            "method" to request.method,
            "params" to params,
        )
    }
    return linkedMapOf(
        "method" to request.eventMethod,
        "workspaceId" to workspaceId,
        "sessionGeneration" to request.sessionGeneration,
        "threadId" to request.threadId,
        "turnId" to request.turnId,
        "conversationId" to request.conversationId,
        "params" to params,
        "message" to message,
        "requestId" to request.requestId,
        "serverRequestMethod" to request.method,
        "serverRequestKey" to request.requestKey,
        "serverRequestDeliveryKey" to
            codexPendingServerRequestDeliveryKey(request.requestKey),
        "serverRequestState" to request.state.name.lowercase(),
        "resolved" to false,
        "actionResult" to "pending",
        "replayed" to replayed,
    )
}

internal data class CodexServerRequestResponseResult(
    val request: CodexPendingServerRequest,
    val resolved: Boolean = false,
    val actionResult: String = "response_sent",
)

internal class CodexServerRequestResponseException(
    val errorCode: String,
    message: String,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

/**
 * Validates generation and session identity before writing a server response.
 *
 * The caller supplies only the already-running session writer. There is no
 * connection callback here by design, so this path can never reconnect.
 */
internal class CodexServerRequestResponder(
    private val registry: CodexServerRequestRegistry,
) {
    suspend fun respond(
        requestedGeneration: Long?,
        activeGeneration: Long,
        activeSessionIdentity: Any?,
        requestId: Any,
        requestedMethod: String?,
        response: Any?,
        responseWriter: (suspend (Any, Any?) -> Unit)?,
    ): CodexServerRequestResponseResult {
        val generation = requestedGeneration
            ?: throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_REQUEST_GENERATION_REQUIRED",
                message = "sessionGeneration is required for Codex server responses.",
            )
        if (generation != activeGeneration || activeSessionIdentity == null) {
            throw CodexServerRequestResponseException(
                errorCode = "CODEX_STALE_SERVER_REQUEST",
                message = "Codex server request belongs to an inactive session generation.",
            )
        }
        val method = requestedMethod?.trim()?.takeIf { it.isNotEmpty() }
            ?: throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_REQUEST_METHOD_REQUIRED",
                message = "serverRequestMethod is required for Codex server responses.",
            )
        val writer = responseWriter
            ?: throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_DISCONNECTED",
                message = "Codex app-server is not connected; response was not sent.",
            )
        val claimed = registry.claimForResponse(
            sessionGeneration = generation,
            sessionIdentity = activeSessionIdentity,
            requestId = requestId,
            expectedMethod = method,
        )
        try {
            writer(claimed.requestId, response)
        } catch (error: Throwable) {
            registry.restorePendingAfterSendFailure(claimed)
            throw CodexServerRequestResponseException(
                errorCode = "CODEX_SERVER_RESPONSE_WRITE_FAILED",
                message = "Failed to write Codex server response.",
                cause = error,
            )
        }
        registry.markResponseSent(claimed)
        return CodexServerRequestResponseResult(request = claimed)
    }
}

internal fun codexServerRequestKey(
    sessionGeneration: Long,
    requestId: Any,
): String {
    val idKey = when (requestId) {
        is Byte, is Short, is Int, is Long ->
            "number:${(requestId as Number).toLong()}"
        is Float, is Double -> {
            val number = (requestId as Number).toDouble()
            if (number.isFinite() && number % 1.0 == 0.0) {
                "number:${number.toLong()}"
            } else {
                "number:$number"
            }
        }
        is String -> "string:$requestId"
        else -> "other:${requestId::class.java.name}:$requestId"
    }
    return "$sessionGeneration/$idKey"
}

internal fun codexPendingServerRequestDeliveryKey(requestKey: String): String {
    return "$requestKey/pending"
}
