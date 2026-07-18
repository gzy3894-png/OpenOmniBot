package cn.com.omnimind.bot.codex

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class CodexAppServerLifecycleRegistryTest {

    @Test
    fun removingOneEngineStreamKeepsOtherEngineListener() {
        val registry = CodexEventListenerRegistry()
        val engineOneEvents = mutableListOf<String>()
        val engineTwoEvents = mutableListOf<String>()
        registry.register("engine-1", "stream-1") {
            engineOneEvents += it["method"].toString()
        }
        registry.register("engine-2", "stream-2") {
            engineTwoEvents += it["method"].toString()
        }

        dispatch(registry, mapOf("method" to "first"))
        registry.unregister("stream-2")
        dispatch(registry, mapOf("method" to "second"))

        assertEquals(listOf("first", "second"), engineOneEvents)
        assertEquals(listOf("first"), engineTwoEvents)
        assertEquals(1, registry.size())
        assertEquals("engine-1", registry.snapshot().single().engineToken)
    }

    @Test
    fun requestIdReuseAcrossGenerationsRejectsStaleResponse() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val oldSession = Any()
        val newSession = Any()
        registry.register(
            sessionGeneration = 1L,
            sessionIdentity = oldSession,
            requestId = 0L,
            method = "item/commandExecution/requestApproval",
            threadId = "old-thread",
            turnId = "old-turn",
        )
        assertEquals(1, registry.invalidateGeneration(1L, oldSession).size)
        val current = registry.register(
            sessionGeneration = 2L,
            sessionIdentity = newSession,
            requestId = 0L,
            method = "item/commandExecution/requestApproval",
            threadId = "new-thread",
            turnId = "new-turn",
        ).request
        var writes = 0

        val staleError = runCatching {
            responder.respond(
                requestedGeneration = 1L,
                activeGeneration = 2L,
                activeSessionIdentity = newSession,
                requestId = 0L,
                requestedMethod = "item/commandExecution/requestApproval",
                response = mapOf("decision" to "accept"),
                responseWriter = { _, _ -> writes += 1 },
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertNotNull(staleError)
        assertEquals("CODEX_STALE_SERVER_REQUEST", staleError?.errorCode)
        assertEquals(0, writes)
        assertSame(current.sessionIdentity, registry.find(2L, 0L)?.sessionIdentity)

        val accepted = responder.respond(
            requestedGeneration = 2L,
            activeGeneration = 2L,
            activeSessionIdentity = newSession,
            requestId = 0L,
            requestedMethod = "item/commandExecution/requestApproval",
            response = mapOf("decision" to "accept"),
            responseWriter = { id, _ ->
                assertEquals(0L, id)
                writes += 1
            },
        )
        assertEquals(1, writes)
        assertEquals(CodexServerRequestState.RESPONSE_SENT, registry.find(2L, 0L)?.state)
        assertEquals("response_sent", accepted.actionResult)
    }

    @Test
    fun disconnectInvalidatesEveryRequestForThatSessionOnly() {
        val registry = CodexServerRequestRegistry()
        val disconnectedSession = Any()
        val otherSession = Any()
        registry.register(
            10L,
            disconnectedSession,
            0L,
            "item/commandExecution/requestApproval",
            "thread-1",
            "turn-1",
        )
        registry.register(
            10L,
            disconnectedSession,
            1L,
            "item/fileChange/requestApproval",
            "thread-1",
            "turn-1",
        )
        registry.register(
            11L,
            otherSession,
            0L,
            "item/permissions/requestApproval",
            "thread-2",
            "turn-2",
        )

        val invalidated = registry.invalidateGeneration(10L, disconnectedSession)

        assertEquals(setOf(0L, 1L), invalidated.map { it.requestId }.toSet())
        assertEquals(1, registry.size())
        assertNotNull(registry.find(11L, 0L))
    }

    @Test
    fun disconnectedResponsePathNeverConsumesPendingOrWrites() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val session = Any()
        registry.register(
            21L,
            session,
            3L,
            "item/commandExecution/requestApproval",
            "thread-1",
            "turn-1",
        )

        val error = runCatching {
            responder.respond(
                requestedGeneration = 21L,
                activeGeneration = 21L,
                activeSessionIdentity = session,
                requestId = 3L,
                requestedMethod = "item/commandExecution/requestApproval",
                response = mapOf("decision" to "decline"),
                responseWriter = null,
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals("CODEX_SERVER_DISCONNECTED", error?.errorCode)
        assertEquals(CodexServerRequestState.PENDING, registry.find(21L, 3L)?.state)
    }

    @Test
    fun firstResponseWinsAcrossEngineCallers() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val session = Any()
        registry.register(
            31L,
            session,
            4L,
            "item/fileChange/requestApproval",
            "thread-1",
            "turn-1",
        )
        var writes = 0
        val writer: suspend (Any, Any?) -> Unit = { _, _ -> writes += 1 }

        responder.respond(
            31L,
            31L,
            session,
            4L,
            "item/fileChange/requestApproval",
            mapOf("decision" to "accept"),
            writer,
        )
        val secondError = runCatching {
            responder.respond(
                31L,
                31L,
                session,
                4L,
                "item/fileChange/requestApproval",
                mapOf("decision" to "decline"),
                writer,
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals(1, writes)
        assertEquals("CODEX_SERVER_REQUEST_ALREADY_RESPONDED", secondError?.errorCode)
    }

    @Test
    fun methodMismatchDoesNotConsumePendingRequest() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val session = Any()
        registry.register(
            41L,
            session,
            5L,
            "item/permissions/requestApproval",
            "thread-1",
            "turn-1",
        )
        var writes = 0

        val error = runCatching {
            responder.respond(
                41L,
                41L,
                session,
                5L,
                "item/commandExecution/requestApproval",
                mapOf("decision" to "accept"),
                responseWriter = { _, _ -> writes += 1 },
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals("CODEX_SERVER_REQUEST_METHOD_MISMATCH", error?.errorCode)
        assertEquals(0, writes)
        assertEquals(CodexServerRequestState.PENDING, registry.find(41L, 5L)?.state)
    }

    @Test
    fun generationAndMethodAreRequiredBeforePendingIsConsumed() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val session = Any()
        registry.register(
            45L,
            session,
            7L,
            "item/commandExecution/requestApproval",
            "thread-1",
            "turn-1",
        )
        var writes = 0
        val writer: suspend (Any, Any?) -> Unit = { _, _ -> writes += 1 }

        val missingGeneration = runCatching {
            responder.respond(
                null,
                45L,
                session,
                7L,
                "item/commandExecution/requestApproval",
                mapOf("decision" to "accept"),
                writer,
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException
        val missingMethod = runCatching {
            responder.respond(
                45L,
                45L,
                session,
                7L,
                null,
                mapOf("decision" to "accept"),
                writer,
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals(
            "CODEX_SERVER_REQUEST_GENERATION_REQUIRED",
            missingGeneration?.errorCode,
        )
        assertEquals(
            "CODEX_SERVER_REQUEST_METHOD_REQUIRED",
            missingMethod?.errorCode,
        )
        assertEquals(0, writes)
        assertEquals(CodexServerRequestState.PENDING, registry.find(45L, 7L)?.state)
    }

    @Test
    fun sameGenerationStillRejectsDifferentSessionIdentity() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val sourceSession = Any()
        val replacementSession = Any()
        registry.register(
            51L,
            sourceSession,
            6L,
            "item/commandExecution/requestApproval",
            "thread-1",
            "turn-1",
        )
        var writes = 0

        val error = runCatching {
            responder.respond(
                51L,
                51L,
                replacementSession,
                6L,
                "item/commandExecution/requestApproval",
                mapOf("decision" to "accept"),
                responseWriter = { _, _ -> writes += 1 },
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals("CODEX_STALE_SERVER_REQUEST", error?.errorCode)
        assertEquals(0, writes)
        assertTrue(registry.find(51L, 6L)?.sessionIdentity === sourceSession)
    }

    @Test
    fun serverMessageBarrierOrdersSessionTransitionAfterSuspendedMessage() =
        runBlocking {
            val barrier = CodexServerMessageBarrier()
            val messageEntered = CompletableDeferred<Unit>()
            val releaseMessage = CompletableDeferred<Unit>()
            val transitionEntered = CompletableDeferred<Unit>()
            val order = mutableListOf<String>()

            val message = launch {
                barrier.run {
                    order += "message-start"
                    messageEntered.complete(Unit)
                    releaseMessage.await()
                    order += "message-end"
                }
            }
            messageEntered.await()
            val transition = launch {
                barrier.run {
                    order += "transition"
                    transitionEntered.complete(Unit)
                }
            }

            yield()
            assertTrue(!transitionEntered.isCompleted)
            releaseMessage.complete(Unit)
            message.join()
            transition.join()

            assertEquals(
                listOf("message-start", "message-end", "transition"),
                order,
            )
        }

    @Test
    fun persistedGenerationIsPositiveAndMonotonicAcrossClockRollback() {
        val first = nextCodexSessionGeneration(
            previousPersisted = 0L,
            nowMillis = 1_000L,
        )
        val sameMillisecondRestart = nextCodexSessionGeneration(
            previousPersisted = first,
            nowMillis = 1_000L,
        )
        val clockRollbackRestart = nextCodexSessionGeneration(
            previousPersisted = sameMillisecondRestart,
            nowMillis = 900L,
        )

        assertEquals(1_000L, first)
        assertEquals(1_001L, sameMillisecondRestart)
        assertEquals(1_002L, clockRollbackRestart)
        assertTrue(clockRollbackRestart > 0L)
    }

    @Test
    fun responseWriteFailureRestoresPendingWithExactErrorCode() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val session = Any()
        registry.register(
            61L,
            session,
            8L,
            "item/commandExecution/requestApproval",
            "thread-1",
            "turn-1",
        )

        val failure = runCatching {
            responder.respond(
                61L,
                61L,
                session,
                8L,
                "item/commandExecution/requestApproval",
                mapOf("decision" to "accept"),
                responseWriter = { _, _ ->
                    throw IllegalStateException("write failed")
                },
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals("CODEX_SERVER_RESPONSE_WRITE_FAILED", failure?.errorCode)
        assertEquals(CodexServerRequestState.PENDING, registry.find(61L, 8L)?.state)
    }

    @Test
    fun resolvedOrUnknownRequestReturnsExactNotPendingCode() = runBlocking {
        val registry = CodexServerRequestRegistry()
        val responder = CodexServerRequestResponder(registry)
        val session = Any()

        val error = runCatching {
            responder.respond(
                71L,
                71L,
                session,
                9L,
                "item/fileChange/requestApproval",
                mapOf("decision" to "decline"),
                responseWriter = { _, _ -> },
            )
        }.exceptionOrNull() as? CodexServerRequestResponseException

        assertEquals("CODEX_SERVER_REQUEST_NOT_PENDING", error?.errorCode)
    }

    private fun dispatch(
        registry: CodexEventListenerRegistry,
        event: Map<String, Any?>,
    ) {
        registry.snapshot().forEach { it.listener(event) }
    }
}
