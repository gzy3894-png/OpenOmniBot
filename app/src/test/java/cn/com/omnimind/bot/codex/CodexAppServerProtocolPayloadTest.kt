package cn.com.omnimind.bot.codex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CodexAppServerProtocolPayloadTest {

    @Test
    fun sanitizeCodexAbsolutePathKeepsLastCleanAbsolutePath() {
        val path = sanitizeCodexAbsolutePath(
            """
            init-host: shell warmup
            /workspace
            warning: ignored trailing log
            """.trimIndent()
        )

        assertEquals("/workspace", path)
    }

    @Test
    fun sanitizeCodexAbsolutePathRejectsRelativeOutput() {
        assertNull(sanitizeCodexAbsolutePath("workspace"))
    }

    @Test
    fun buildCodexTextInputMatchesAppServerTextShape() {
        val input = buildCodexTextInput(" hello ")

        assertEquals(1, input.size)
        assertEquals("text", input[0]["type"])
        assertEquals("hello", input[0]["text"])
        assertTrue(input[0].containsKey("text_elements"))
    }

    @Test
    fun buildDefaultCodexSandboxPolicyUsesAbsoluteWritableRoot() {
        val policy = buildDefaultCodexSandboxPolicy("noise\n/workspace")

        assertEquals("workspaceWrite", policy["type"])
        assertEquals(listOf("/workspace"), policy["writableRoots"])
        assertEquals(true, policy["networkAccess"])
        assertEquals(false, policy["excludeTmpdirEnvVar"])
        assertEquals(false, policy["excludeSlashTmp"])
    }

    @Test
    fun resolveCodexSandboxModeUsesKebabSandboxModeString() {
        assertEquals(
            "workspace-write",
            resolveCodexSandboxMode(mapOf("sandbox" to "workspace-write")),
        )
        assertEquals(
            "danger-full-access",
            resolveCodexSandboxMode(mapOf("sandbox" to "danger-full-access")),
        )
        assertEquals(
            "read-only",
            resolveCodexSandboxMode(mapOf("sandbox" to "read-only")),
        )
        assertEquals(
            "danger-full-access",
            resolveCodexSandboxMode(
                mapOf("sandboxPolicy" to mapOf("type" to "dangerFullAccess")),
            ),
        )
        assertEquals(
            "workspace-write",
            resolveCodexSandboxMode(
                mapOf(
                    "sandboxPolicy" to mapOf(
                        "type" to "workspaceWrite",
                        "writableRoots" to emptyList<String>(),
                    ),
                ),
            ),
        )
        // Prefer explicit sandbox over policy object.
        assertEquals(
            "read-only",
            resolveCodexSandboxMode(
                mapOf(
                    "sandbox" to "read-only",
                    "sandboxPolicy" to mapOf("type" to "dangerFullAccess"),
                ),
            ),
        )
    }

    @Test
    fun resolveCodexSandboxPolicyFillsEmptyWritableRootsFromCwd() {
        val policy = resolveCodexSandboxPolicy(
            mapOf(
                "type" to "workspaceWrite",
                "writableRoots" to emptyList<String>(),
                "networkAccess" to true,
                "excludeTmpdirEnvVar" to false,
                "excludeSlashTmp" to false,
            ),
            "/workspace/project",
        )

        assertEquals("workspaceWrite", policy["type"])
        assertEquals(listOf("/workspace/project"), policy["writableRoots"])
        assertEquals(true, policy["networkAccess"])
    }

    @Test
    fun resolveCodexSandboxPolicyPreservesNonEmptyRootsAndFullAccess() {
        val kept = resolveCodexSandboxPolicy(
            mapOf(
                "type" to "workspaceWrite",
                "writableRoots" to listOf("/custom/root"),
                "networkAccess" to false,
            ),
            "/workspace",
        )
        assertEquals(listOf("/custom/root"), kept["writableRoots"])
        assertEquals(false, kept["networkAccess"])

        val full = resolveCodexSandboxPolicy(
            mapOf("type" to "dangerFullAccess"),
            "/workspace",
        )
        assertEquals("dangerFullAccess", full["type"])
        assertNull(full["writableRoots"])
    }

    @Test
    fun addCodexOptionalRunParamsForwardsModelAndPlanMode() {
        val params = linkedMapOf<String, Any?>("threadId" to "thread-1")

        addCodexOptionalRunParams(
            params,
            mapOf(
                "model" to "gpt-5-codex",
                "effort" to "high",
                "collaborationMode" to "plan",
                "serviceTier" to "auto"
            )
        )

        assertEquals("gpt-5-codex", params["model"])
        assertEquals("high", params["effort"])
        val collaborationMode = params["collaborationMode"] as? Map<*, *>
        val settings = collaborationMode?.get("settings") as? Map<*, *>
        assertEquals("plan", collaborationMode?.get("mode"))
        assertEquals("gpt-5-codex", settings?.get("model"))
        assertEquals("high", settings?.get("reasoning_effort"))
        assertEquals("auto", params["serviceTier"])
    }

    @Test
    fun resolveCodexCollaborationModeFillsStructuredModeSettings() {
        val mode = resolveCodexCollaborationMode(
            mapOf(
                "model" to "gpt-5-codex",
                "collaborationMode" to mapOf(
                    "mode" to "plan",
                    "settings" to mapOf("developer_instructions" to "Use a checklist.")
                )
            )
        )
        val settings = mode?.get("settings") as? Map<*, *>

        assertEquals("plan", mode?.get("mode"))
        assertEquals("gpt-5-codex", settings?.get("model"))
        assertEquals("Use a checklist.", settings?.get("developer_instructions"))
    }

    @Test
    fun resolveCodexCollaborationModeRequiresModel() {
        val params = linkedMapOf<String, Any?>("threadId" to "thread-1")

        addCodexOptionalRunParams(
            params,
            mapOf("collaborationMode" to "plan")
        )

        assertEquals(false, params.containsKey("collaborationMode"))
    }

    @Test
    fun resolveCodexReviewTargetDefaultsToUncommittedChanges() {
        val target = resolveCodexReviewTarget(null)

        assertEquals("uncommittedChanges", target["type"])
    }

    @Test
    fun resolveCodexReviewTargetPreservesExplicitTarget() {
        val target = resolveCodexReviewTarget(
            mapOf(
                "type" to "baseBranch",
                "branch" to "main"
            )
        )

        assertEquals("baseBranch", target["type"])
        assertEquals("main", target["branch"])
    }

    @Test
    fun remoteBridgeConfigRequiresUrlAndCwd() {
        assertTrue(
            CodexRemoteBridgeConfig(
                bridgeUrl = "ws://127.0.0.1:17321/codex",
                cwd = "/Users/ocean/code/project"
            ).isConfigured
        )
        assertEquals(
            false,
            CodexRemoteBridgeConfig(
                bridgeUrl = "ws://127.0.0.1:17321/codex",
                cwd = ""
            ).isConfigured
        )
    }

    @Test
    fun normalizeBridgeUrlsAcceptHostPortAndDefaultPaths() {
        assertEquals(
            "ws://192.168.1.10:17321/codex",
            normalizeCodexBridgeWebSocketUrl("192.168.1.10:17321")
        )
        assertEquals(
            "http://192.168.1.10:17321/health",
            normalizeCodexBridgeHealthUrl("ws://192.168.1.10:17321/codex")
        )
        assertEquals(
            "http://192.168.1.10:17321/fs/list",
            normalizeCodexBridgeFsListUrl("ws://192.168.1.10:17321/codex")
        )
    }

    @Test
    fun defaultThreadSourceKindsUseCurrentCodexAppServerVariants() {
        assertTrue(DEFAULT_CODEX_THREAD_SOURCE_KINDS.contains("cli"))
        assertTrue(DEFAULT_CODEX_THREAD_SOURCE_KINDS.contains("appServer"))
        assertTrue(DEFAULT_CODEX_THREAD_SOURCE_KINDS.contains("subAgentOther"))
        assertEquals(false, DEFAULT_CODEX_THREAD_SOURCE_KINDS.contains("interactive"))
        assertEquals(false, DEFAULT_CODEX_THREAD_SOURCE_KINDS.contains("background"))
        assertEquals(false, DEFAULT_CODEX_THREAD_SOURCE_KINDS.contains("subAgentInteractive"))
    }

    @Test
    fun withLocalIdsInjectsActiveAndActiveTurnIdWhenActive() {
        val response = mapOf<String, Any?>("thread" to mapOf("id" to "thread-1"))

        val enriched = response.withLocalIds(
            threadId = "thread-1",
            conversationId = 42L,
            turnId = "turn-7",
            active = true,
        )

        assertEquals("thread-1", enriched["threadId"])
        assertEquals(42L, enriched["conversationId"])
        assertEquals("turn-7", enriched["turnId"])
        assertEquals("turn-7", enriched["activeTurnId"])
        assertEquals(true, enriched["active"])
    }

    @Test
    fun withLocalIdsSurfacesInactiveWithoutActiveTurnId() {
        val response = mapOf<String, Any?>("thread" to mapOf("id" to "thread-1"))

        val enriched = response.withLocalIds(
            threadId = "thread-1",
            conversationId = 99L,
            turnId = null,
            active = false,
        )

        assertEquals(false, enriched["active"])
        assertNull(enriched["turnId"])
        assertNull(enriched["activeTurnId"])
    }

    @Test
    fun withLocalIdsOmitsActiveFieldsWhenNotProvided() {
        val response = mapOf<String, Any?>("thread" to mapOf("id" to "thread-1"))

        val enriched = response.withLocalIds(
            threadId = "thread-1",
            conversationId = null,
        )

        assertEquals("thread-1", enriched["threadId"])
        assertEquals(false, enriched.containsKey("active"))
        assertEquals(false, enriched.containsKey("activeTurnId"))
        assertEquals(false, enriched.containsKey("turnId"))
    }

    @Test
    fun normalizeCodexServiceTierTreatsOffAsNullWithoutAffectingFastMode() {
        assertNull(normalizeCodexServiceTier("off"))
        assertNull(normalizeCodexServiceTier("false"))
        assertNull(normalizeCodexServiceTier("default"))
        assertEquals("fast", normalizeCodexServiceTier("fast"))
        assertEquals("fast", normalizeCodexServiceTier("priority"))
    }

    @Test
    fun resolveCodexFastModePrefersExplicitBooleanOverServiceTier() {
        assertEquals(
            false,
            resolveCodexFastMode(
                requestedFastMode = false,
                serviceTier = "fast",
                serviceTierArgPresent = true,
                existingFastMode = true,
            )
        )
        assertEquals(
            true,
            resolveCodexFastMode(
                requestedFastMode = true,
                serviceTier = "off",
                serviceTierArgPresent = true,
                existingFastMode = false,
            )
        )
    }

    @Test
    fun resolveCodexFastModeUsesServiceTierWhenBooleanAbsent() {
        assertEquals(
            true,
            resolveCodexFastMode(
                requestedFastMode = null,
                serviceTier = "fast",
                serviceTierArgPresent = true,
                existingFastMode = false,
            )
        )
        assertEquals(
            false,
            resolveCodexFastMode(
                requestedFastMode = null,
                serviceTier = "off",
                serviceTierArgPresent = true,
                existingFastMode = true,
            )
        )
        assertEquals(
            true,
            resolveCodexFastMode(
                requestedFastMode = null,
                serviceTier = null,
                serviceTierArgPresent = false,
                existingFastMode = true,
            )
        )
        assertEquals(
            false,
            resolveCodexFastMode(
                requestedFastMode = null,
                serviceTier = null,
                serviceTierArgPresent = false,
                existingFastMode = null,
            )
        )
    }

    @Test
    fun buildCodexConfigTomlWritesExplicitFastModeFalseAndDropsFastServiceTier() {
        val toml = buildCodexConfigToml(
            baseUrl = "https://example.test/v1",
            model = "gpt-test",
            serviceTier = "fast",
            fastMode = false,
            existingFeatures = mapOf(
                "auto_compaction" to "true",
                "hooks" to "true",
                "goals" to "true",
                "fast_mode" to "true",
            ),
        )

        assertTrue(toml.contains("[features]"))
        assertTrue(toml.contains("fast_mode = false"))
        assertTrue(toml.contains("auto_compaction = true"))
        assertTrue(toml.contains("hooks = true"))
        assertTrue(toml.contains("goals = true"))
        assertEquals(false, toml.contains("service_tier = \"fast\""))
        // Must never "turn off" by deleting the key.
        assertTrue(Regex("""(?m)^\s*fast_mode\s*=\s*false\s*$""").containsMatchIn(toml))
    }

    @Test
    fun buildCodexFeaturesTomlSectionWritesAutoCompactionExplicitly() {
        val off = buildCodexFeaturesTomlSection(
            fastMode = false,
            autoCompaction = false,
            existingFeatures = mapOf(
                "auto_compaction" to "true",
                "hooks" to "true",
                "goals" to "true",
            ),
        ).joinToString("\n")
        assertTrue(off.contains("auto_compaction = false"))
        assertTrue(off.contains("hooks = true"))
        assertTrue(off.contains("goals = true"))
        assertTrue(off.contains("fast_mode = false"))

        val on = buildCodexFeaturesTomlSection(
            fastMode = true,
            autoCompaction = true,
            existingFeatures = mapOf("hooks" to "false"),
        ).joinToString("\n")
        assertTrue(on.contains("auto_compaction = true"))
        assertTrue(on.contains("hooks = false"))
        assertTrue(on.contains("fast_mode = true"))

        // null autoCompaction preserves existing, does not invent the key.
        val keep = buildCodexFeaturesTomlSection(
            fastMode = false,
            autoCompaction = null,
            existingFeatures = mapOf("auto_compaction" to "true", "goals" to "true"),
        ).joinToString("\n")
        assertTrue(keep.contains("auto_compaction = true"))
        assertTrue(keep.contains("goals = true"))
    }

        fun buildCodexConfigTomlWritesFastModeTrueAndServiceTierFast() {
        val toml = buildCodexConfigToml(
            baseUrl = "https://example.test/v1",
            model = "gpt-test",
            serviceTier = "fast",
            fastMode = true,
        )

        assertTrue(toml.contains("fast_mode = true"))
        assertTrue(toml.contains("service_tier = \"fast\""))
    }

    @Test
    fun buildCodexConfigTomlMergesFeaturesAndPreservesOtherTables() {
        val existing = """
            model = "old"
            service_tier = "fast"
            approval_policy = "never"
            sandbox_mode = "danger-full-access"

            [features]
            auto_compaction = true
            hooks = true
            goals = true
            fast_mode = true

            [projects."/root"]
            trust_level = "trusted"

            [model_providers.omnimind]
            name = "omnimind"
            base_url = "https://old.example/v1"
        """.trimIndent()

        val features = extractTomlTableEntries(existing, "features")
        val toml = buildCodexConfigToml(
            baseUrl = "https://new.example/v1",
            model = "gpt-new",
            serviceTier = null,
            fastMode = false,
            existingFeatures = features,
            existingToml = existing,
        )

        assertTrue(toml.contains("fast_mode = false"))
        assertTrue(toml.contains("auto_compaction = true"))
        assertTrue(toml.contains("hooks = true"))
        assertTrue(toml.contains("goals = true"))
        assertTrue(toml.contains("approval_policy = \"never\"") || toml.contains("approval_policy = never"))
        assertTrue(toml.contains("[projects.\"/root\"]"))
        assertTrue(toml.contains("trust_level = \"trusted\""))
        assertTrue(toml.contains("base_url = \"https://new.example/v1\""))
        assertEquals(false, toml.contains("service_tier = \"fast\""))
        // Managed omnimind provider is rewritten; old base_url must not stick around.
        assertEquals(false, toml.contains("https://old.example/v1"))
    }

    @Test
    fun extractTomlBooleanSupportsBareAndQuotedValues() {
        val body = """
            fast_mode = true
            goals = "false"
            hooks = FALSE
        """.trimIndent()

        assertEquals(true, extractTomlBoolean(body, "fast_mode"))
        assertEquals(false, extractTomlBoolean(body, "goals"))
        assertEquals(false, extractTomlBoolean(body, "hooks"))
        assertNull(extractTomlBoolean(body, "missing"))
    }

    @Test
    fun buildCodexConfigTomlWritesContextTokenThresholdAndClamp() {
        val written = buildCodexConfigToml(
            baseUrl = "https://example.test/v1",
            model = "gpt-test",
            contextTokenThreshold = 128000,
        )
        assertTrue(written.contains("omnimind_context_token_threshold = 128000"))

        val clampedLow = buildCodexConfigToml(
            baseUrl = "https://example.test/v1",
            model = "gpt-test",
            contextTokenThreshold = 100,
        )
        assertTrue(clampedLow.contains("omnimind_context_token_threshold = 10000"))

        val omitted = buildCodexConfigToml(
            baseUrl = "https://example.test/v1",
            model = "gpt-test",
            contextTokenThreshold = null,
        )
        assertEquals(false, omitted.contains("omnimind_context_token_threshold"))
    }

    @Test
    fun extractTomlIntParsesBareAndQuotedValues() {
        val body = """
            omnimind_context_token_threshold = 128000
            other = "64000"
        """.trimIndent()
        assertEquals(128000, extractTomlInt(body, "omnimind_context_token_threshold"))
        assertEquals(64000, extractTomlInt(body, "other"))
        assertNull(extractTomlInt(body, "missing"))
        assertEquals(10000, clampContextTokenThreshold(1))
        assertEquals(1_000_000, clampContextTokenThreshold(9_999_999))
    }

    @Test
    fun extractTomlTableBodyStopsAtNextHeader() {
        val source = """
            [features]
            fast_mode = true
            goals = true

            [projects."/root"]
            trust_level = "trusted"
        """.trimIndent()

        val body = extractTomlTableBody(source, "features")
        assertTrue(body.contains("fast_mode = true"))
        assertTrue(body.contains("goals = true"))
        assertEquals(false, body.contains("trust_level"))
    }
}
