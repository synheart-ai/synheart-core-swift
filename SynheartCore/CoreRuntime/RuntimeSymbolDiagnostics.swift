import Foundation

/// Snapshot of the C ABI surface exported by the loaded native runtime.
public struct RuntimeSymbolDiagnostics: Equatable, Sendable {
    public let runtimeEntrypointFound: Bool
    public let missingRequiredSymbols: [String]
    public let missingOptionalSymbols: [String]

    /// Required symbols are the minimum contract needed for the SDK's core
    /// lifecycle, signal ingestion, persistence, and state delivery paths.
    public var isCompatible: Bool {
        runtimeEntrypointFound && missingRequiredSymbols.isEmpty
    }
}

/// Snapshot of native libraries that must be supplied by the host app.
///
/// The iOS stable/lab runtime deliberately leaves ONNX Runtime to the host so
/// that one copy can be shared by the app. Edge runtimes do not use ONNX and
/// therefore do not require this dependency.
public struct RuntimeDependencyDiagnostics: Equatable, Sendable {
    public let requiresExternalONNXRuntime: Bool
    public let onnxRuntimeEntrypointFound: Bool
    public let missingRequiredDependencies: [String]

    public var isCompatible: Bool {
        missingRequiredDependencies.isEmpty
    }
}

enum RuntimeDependencyManifest {
    static let edgeRuntimeMarker = "synheart_core_edge_create"
    static let onnxRuntimeEntrypoint = "OrtGetApiBase"
    static let onnxRuntimeDependency = "onnxruntime-c (OrtGetApiBase)"

    static func audit(
        runtimeEntrypointFound: Bool,
        edgeRuntimeFound: Bool,
        onnxRuntimeEntrypointFound: Bool
    ) -> RuntimeDependencyDiagnostics {
        // No host dependency can be inferred until a native runtime is linked.
        // An edge runtime contains the marker above and never loads ONNX.
        let requiresExternalONNXRuntime = runtimeEntrypointFound && !edgeRuntimeFound
        let missing = requiresExternalONNXRuntime && !onnxRuntimeEntrypointFound
            ? [onnxRuntimeDependency]
            : []

        return RuntimeDependencyDiagnostics(
            requiresExternalONNXRuntime: requiresExternalONNXRuntime,
            onnxRuntimeEntrypointFound: onnxRuntimeEntrypointFound,
            missingRequiredDependencies: missing
        )
    }
}

/// Single source of truth for required versus additive runtime capabilities.
enum RuntimeSymbolManifest {
    static let required: Set<String> = [
        "synheart_core_new",
        "synheart_core_free",
        "synheart_core_free_string",
        "synheart_core_start_session",
        "synheart_core_stop_session",
        "synheart_core_current_session",
        "synheart_core_is_running",
        "synheart_core_push_rr",
        "synheart_core_push_hr",
        "synheart_core_push_accel",
        "synheart_core_push_behavior",
        "synheart_core_ingest_batch",
        "synheart_core_list_sessions",
        "synheart_core_get_session_summary",
        "synheart_core_get_hsi_windows",
        "synheart_core_get_storage_usage",
        "synheart_core_delete_session",
        "synheart_core_wipe_local_data",
        "synheart_core_set_retention_days",
        "synheart_core_set_sync_enabled",
        "synheart_core_sync_now",
        "synheart_core_sync_status",
        "synheart_core_set_hsi_callback",
        "synheart_core_clear_hsi_callback",
        "synheart_core_current_consent",
        "synheart_core_grant_consent",
        "synheart_core_revoke_consent",
        "synheart_core_has_consent",
        "synheart_core_consent_clear_stored",
        "synheart_core_consent_effective_state",
    ]

    static let optional: Set<String> = [
        "synheart_core_abort_session",
        "synheart_core_baselines_json",
        "synheart_core_breathing_evaluate",
        "synheart_core_breathing_reset",
        "synheart_core_breathing_set_population",
        "synheart_core_breathing_set_target_bpm",
        "synheart_core_breathing_set_window_secs",
        "synheart_core_build_info",
        "synheart_core_cancel_account_deletion",
        "synheart_core_close_orphan_session",
        "synheart_core_consent_configure_cloud",
        "synheart_core_consent_get_editable_form",
        "synheart_core_consent_needs_token_refresh",
        "synheart_core_consent_status",
        "synheart_core_consent_submit_form",
        "synheart_core_diagnostics",
        "synheart_core_enqueue_hsi",
        "synheart_core_enrol_study",
        "synheart_core_export_srm_snapshot",
        "synheart_core_flush_uploads",
        "synheart_core_get_ambient_capture",
        "synheart_core_get_subject_id",
        "synheart_core_is_network_reachable",
        "synheart_core_is_runtime_available",
        "synheart_core_is_lab_available",
        "synheart_core_lab_close_window",
        "synheart_core_lab_finalize",
        "synheart_core_lab_merge_extra_data",
        "synheart_core_lab_open_window",
        "synheart_core_lab_set_state_overrides",
        "synheart_core_lab_set_window_values",
        "synheart_core_lab_start",
        "synheart_core_last_error",
        "synheart_core_last_error_code",
        "synheart_core_last_ingest_success_at_ms",
        "synheart_core_load_capability_token",
        "synheart_core_load_srm_snapshot",
        "synheart_core_priority_effective_rank",
        "synheart_core_priority_resolve",
        "synheart_core_priority_set_metric_override",
        "synheart_core_priority_set_provider",
        "synheart_core_push_sleep_stages",
        "synheart_core_rebind_subject_id",
        "synheart_core_record_metric",
        "synheart_core_request_account_deletion",
        "synheart_core_request_study_data_deletion",
        "synheart_core_resilience_compute_v1",
        "synheart_core_sdk_device_auth_status",
        "synheart_core_sdk_register_device",
        "synheart_core_sdk_reattest_device",
        "synheart_core_sdk_logout",
        "synheart_core_sdk_set_crypto_callbacks",
        "synheart_core_set_ambient_capture",
        "synheart_core_set_storage_callbacks",
        "synheart_core_srm_overall_status",
        "synheart_core_srm_push_wearable_daily",
        "synheart_core_srm_trigger_wearable_recompute",
        "synheart_core_stop_session_v2",
        "synheart_core_upload_metadata",
        "synheart_core_upload_queue_length",
        "synheart_core_validate_study_codes",
        "synheart_core_wellness_json",
        "synheart_core_wearable_reference_json",
        "synheart_core_withdraw_study",
        // Additive sync-space lifecycle.
        "synheart_core_sync_create_space",
        "synheart_core_sync_generate_pairing",
        "synheart_core_sync_join_space",
        "synheart_core_sync_readiness",
        "synheart_core_sync_recover_space",
        "synheart_core_sync_leave_space",
        "synheart_core_sync_list_devices",
        "synheart_core_sync_revoke_device",
        "synheart_core_sync_delete_space",
        "synheart_core_sync_clear_local_space",
        // Typed baseline transport and score computation.
        "synheart_core_baseline_hydrate_local",
        "synheart_core_baseline_export_offline",
        "synheart_core_baseline_import_offline",
        "synheart_core_sleep_score_compute_json",
        "synheart_core_recovery_score_compute_json",
        "synheart_core_readiness_score_compute_json",
        "synheart_core_attach_sleep_score_json",
        "synheart_core_attach_recovery_score_today",
        "synheart_core_clear_recovery_score_today",
        "synheart_core_last_sleep_score_json",
        "synheart_core_export_longitudinal_snapshot",
        "synheart_core_load_longitudinal_snapshot",
        // Data rights and research enrollment.
        "synheart_core_request_data_deletion",
        "synheart_core_get_data_deletion",
        "synheart_core_list_data_deletions",
        "synheart_core_research_study_status",
        "synheart_core_record_study_consent",
        // Bulk/vendor ingestion, history, and personalization.
        "synheart_core_push_rr_batch",
        "synheart_core_push_vendor_hrv",
        "synheart_core_push_vendor_vitals",
        "synheart_core_ingest_vendor_event",
        "synheart_core_query_vendor_events",
        "synheart_core_get_latest_vendor_event",
        "synheart_core_delete_vendor_events_for_provider",
        "synheart_core_hsi_history_list",
        "synheart_core_fetch_cloud_hsi",
        "synheart_core_hsi_history_count",
        "synheart_core_hsi_history_clear",
        "synheart_core_set_task_type",
        "synheart_core_current_task_type",
        "synheart_core_set_focus_kind",
        "synheart_core_current_focus_kind",
        "synheart_core_current_workout_kind",
        "synheart_core_push_workout_event",
        "synheart_core_personalization_context_json",
        // Runtime stream, buffered logging, and Syni cloud service.
        "synheart_core_init_logging_buffered",
        "synheart_core_drain_logs",
        "synheart_core_dropped_log_lines",
        "synheart_core_shutdown_logging",
        "synheart_core_stream_start",
        "synheart_core_stream_stop",
        "synheart_core_stream_state",
        "synheart_core_syni_chat",
        "synheart_core_syni_list_sessions",
        "synheart_core_syni_get_session",
        "synheart_core_syni_get_session_messages",
        "synheart_core_syni_close_session",
    ]

    static var all: Set<String> {
        required.union(optional)
    }

    static func audit(resolvedSymbols: Set<String>) -> RuntimeSymbolDiagnostics {
        RuntimeSymbolDiagnostics(
            runtimeEntrypointFound: resolvedSymbols.contains("synheart_core_new"),
            missingRequiredSymbols: required.subtracting(resolvedSymbols).sorted(),
            missingOptionalSymbols: optional.subtracting(resolvedSymbols).sorted()
        )
    }
}
