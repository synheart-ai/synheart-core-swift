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
        "synheart_core_set_hsi_callback",
        "synheart_core_clear_hsi_callback",
    ]

    static let optional: Set<String> = [
        "synheart_core_baselines_json",
        "synheart_core_breathing_evaluate",
        "synheart_core_breathing_reset",
        "synheart_core_breathing_set_population",
        "synheart_core_breathing_set_target_bpm",
        "synheart_core_breathing_set_window_secs",
        "synheart_core_cancel_account_deletion",
        "synheart_core_consent_clear_stored",
        "synheart_core_consent_configure_cloud",
        "synheart_core_consent_effective_state",
        "synheart_core_consent_get_editable_form",
        "synheart_core_consent_needs_token_refresh",
        "synheart_core_consent_status",
        "synheart_core_consent_submit_form",
        "synheart_core_current_consent",
        "synheart_core_diagnostics",
        "synheart_core_enqueue_hsi",
        "synheart_core_enrol_study",
        "synheart_core_export_srm_snapshot",
        "synheart_core_flush_uploads",
        "synheart_core_get_ambient_capture",
        "synheart_core_get_subject_id",
        "synheart_core_grant_consent",
        "synheart_core_has_consent",
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
        "synheart_core_revoke_consent",
        "synheart_core_sdk_device_auth_status",
        "synheart_core_sdk_register_device",
        "synheart_core_sdk_set_crypto_callbacks",
        "synheart_core_set_ambient_capture",
        "synheart_core_set_storage_callbacks",
        "synheart_core_srm_overall_status",
        "synheart_core_srm_push_wearable_daily",
        "synheart_core_srm_trigger_wearable_recompute",
        "synheart_core_upload_metadata",
        "synheart_core_upload_queue_length",
        "synheart_core_validate_study_codes",
        "synheart_core_wellness_json",
        "synheart_core_wearable_reference_json",
        "synheart_core_withdraw_study",
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
