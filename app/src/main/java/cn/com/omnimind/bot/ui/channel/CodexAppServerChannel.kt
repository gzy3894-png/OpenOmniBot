package cn.com.omnimind.bot.ui.channel

import android.content.Context
import cn.com.omnimind.bot.codex.CodexAppServerManager
import cn.com.omnimind.bot.codex.CodexServerRequestResponseException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

class CodexAppServerChannel {
    companion object {
        private const val METHOD_CHANNEL = "cn.com.omnimind.bot/CodexAppServer"
        private const val EVENT_CHANNEL = "cn.com.omnimind.bot/CodexAppServerEvents"
        private val NEXT_CHANNEL_TOKEN = AtomicLong(0L)
        private val NEXT_STREAM_OWNER_TOKEN = AtomicLong(0L)
        /**
         * A rebuilt Activity can configure the same cached FlutterEngine before
         * the old ChannelManager finishes clearing. Only the latest channel
         * instance may detach handlers from that engine's messenger.
         */
        private val ACTIVE_ENGINE_OWNERS = ConcurrentHashMap<Int, Long>()
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val channelToken = NEXT_CHANNEL_TOKEN.incrementAndGet()
    private var context: Context? = null
    private var manager: CodexAppServerManager? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var eventStreamToken: String? = null
    private var eventStreamOwnerToken: Long? = null
    private var activeStreamHandlerOwnerToken: Long? = null
    private var engineToken: String = "flutter-engine-unbound-$channelToken"
    private var boundEngineKey: Int? = null

    fun onCreate(context: Context) {
        this.context = context.applicationContext
        manager = CodexAppServerManager.getInstance(context.applicationContext)
        val sink = eventSink
        val ownerToken = eventStreamOwnerToken
        if (sink != null && ownerToken != null) {
            registerEventSink(sink, ownerToken)
        }
    }

    fun setChannel(flutterEngine: FlutterEngine) {
        // B38 T5: tear down prior handlers first so re-configure on the same
        // engine (or messenger reuse) never leaves a null handler race that
        // surfaces as Flutter MissingPluginException(connect).
        detachChannels(reason = "channel_reconfigured")
        engineToken = "flutter-engine-${Integer.toHexString(System.identityHashCode(flutterEngine))}-$channelToken"

        val engineKey = System.identityHashCode(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Claim before installing handlers. A delayed clear from the previous
        // Activity will then observe the new owner and leave these handlers intact.
        ACTIVE_ENGINE_OWNERS[engineKey] = channelToken
        boundEngineKey = engineKey
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(::handleMethodCall)

        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        val streamOwnerToken = NEXT_STREAM_OWNER_TOKEN.incrementAndGet()
        activeStreamHandlerOwnerToken = streamOwnerToken
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                if (activeStreamHandlerOwnerToken != streamOwnerToken) {
                    return
                }
                unregisterEventSink(reason = "stream_replaced")
                eventSink = events
                eventStreamOwnerToken = streamOwnerToken
                events?.let { registerEventSink(it, streamOwnerToken) }
            }

            override fun onCancel(arguments: Any?) {
                if (activeStreamHandlerOwnerToken != streamOwnerToken ||
                    eventStreamOwnerToken != streamOwnerToken
                ) {
                    return
                }
                unregisterEventSink(reason = "stream_cancelled")
                eventSink = null
                eventStreamOwnerToken = null
            }
        })
    }

    private fun registerEventSink(
        sink: EventChannel.EventSink,
        ownerToken: Long,
    ) {
        if (eventStreamOwnerToken != ownerToken ||
            activeStreamHandlerOwnerToken != ownerToken
        ) {
            return
        }
        val safeManager = manager
            ?: context?.let { CodexAppServerManager.getInstance(it) }
            ?: return
        manager = safeManager
        eventStreamToken = safeManager.registerEventListener(
            engineToken = engineToken,
            listener = { payload -> sink.success(payload) },
        )
    }

    private fun unregisterEventSink(reason: String) {
        val streamToken = eventStreamToken ?: return
        eventStreamToken = null
        manager?.unregisterEventListener(
            streamToken = streamToken,
            reason = reason,
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val safeContext = context
        if (safeContext == null) {
            result.error("CODEX_CONTEXT_ERROR", "Context not initialized", null)
            return
        }
        val arguments = (call.arguments as? Map<*, *>)
            ?.entries
            ?.associate { (key, value) -> key.toString() to value }
            .orEmpty()

        scope.launch {
            runCatching {
                CodexAppServerManager
                    .getInstance(safeContext)
                    .handleMethod(
                        method = call.method,
                        args = arguments,
                        callerEngineToken = engineToken,
                    )
            }.onSuccess { payload ->
                result.success(payload)
            }.onFailure { error ->
                result.error(
                    (error as? CodexServerRequestResponseException)?.errorCode
                        ?: "CODEX_APP_SERVER_CALL_FAILED",
                    error.message ?: error.javaClass.simpleName,
                    null
                )
            }
        }
    }

    fun clear() {
        detachChannels(reason = "channel_cleared")
        manager = null
        context = null
    }

    private fun detachChannels(reason: String) {
        unregisterEventSink(reason = reason)
        eventSink = null
        eventStreamOwnerToken = null
        activeStreamHandlerOwnerToken = null
        val engineKey = boundEngineKey
        val stillOwnsEngine = engineKey != null &&
            ACTIVE_ENGINE_OWNERS.remove(engineKey, channelToken)
        if (stillOwnsEngine) {
            // Keep a structured failure handler during engine teardown instead
            // of exposing a transient MissingPluginException to Dart. A new
            // ChannelManager overwrites this after claiming ownership.
            methodChannel?.setMethodCallHandler { call, result ->
                result.error(
                    "CODEX_CHANNEL_DETACHED",
                    "Codex channel is detached while FlutterEngine is reconfiguring.",
                    mapOf("method" to call.method),
                )
            }
            eventChannel?.setStreamHandler(null)
        }
        methodChannel = null
        eventChannel = null
        boundEngineKey = null
    }
}
