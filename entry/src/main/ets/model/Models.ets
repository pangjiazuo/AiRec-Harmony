export type JsonObject = Record<string, Object>;
export type AppearanceMode = 'light' | 'dark' | 'system';
export type EventType = 'person' | 'vehicle' | 'animal' | 'dwell';
export interface ClientPreferences { endpoint: string; appearance: AppearanceMode; }

export interface Detection {
  category: string; bbox: number[]; dwell_seconds: number; dwell_reached: boolean;
}
export interface ChannelStatus {
  id: number; name: string; enabled: boolean; state: string; recording: boolean;
  preview_fps: number; recording_fps: number; capture_fps: number; detections: Detection[]; error: string;
}
export interface MemoryInfo { used_bytes: number; total_bytes: number; available_bytes: number; used_percent: number; }
export interface SystemInfo { hostname: string; cpu_percent: number; temperature_c: number; memory: MemoryInfo; }
export interface StorageStatus {
  target_id: string; label: string; free_bytes: number; total_bytes: number; used_bytes: number; error: string;
}
export interface DetectorStatus { ready: boolean; model: string; backend: string; error: string; }
export interface RecorderStatus {
  channels: ChannelStatus[]; system: SystemInfo; storage: StorageStatus; detector: DetectorStatus; uptime_seconds: number;
}
export interface RecordingItem {
  id: string; channel_id: number; created_at: string; duration_seconds: number; size_bytes: number;
  url: string; available: boolean; error: string;
}
export interface EventItem {
  id: string; channel_id: number; created_at: string; event_type: string; category: string; label: string;
  dwell_seconds: number; snapshot_url: string; recording_url: string; recording_available: boolean; available: boolean;
}
export interface HardwareUse { used: boolean; }
export interface ModelInfo {
  name: string; version: string; tracker: string; backend_label: string; sdk_version: string;
  npu: HardwareUse; vpu: HardwareUse; limitations: string[]; error: string;
}
export interface StorageTarget {
  id: string; label: string; available: boolean; writable: boolean; free_bytes: number; total_bytes: number; error: string;
}
export interface StorageTargets { selected_id: string; targets: StorageTarget[]; }
export interface RecordingConfig { enabled: boolean; segment_minutes: number; }
export interface DetectionConfig {
  enabled: boolean; categories: string[]; threshold_seconds: number; confidence: number;
  sample_interval: number; lost_tolerance_seconds: number;
}
export interface PrivacyConfig { face_mosaic: boolean; plate_mosaic: boolean; }
export interface PrivacyPatch { face_mosaic?: boolean; plate_mosaic?: boolean; }
export interface ChannelConfig {
  id: number; name: string; enabled: boolean; source: string; crop: number[];
  width: number; height: number; fps: number; preview_fps: number;
  recording: RecordingConfig; detection: DetectionConfig; privacy?: PrivacyConfig;
}
export interface StorageConfig { target_id: string; max_gb: number; min_free_gb: number; }
/** raw 保留后端扩展字段，客户端保存时不会重建整个配置。 */
export interface RecorderConfig { channels: ChannelConfig[]; storage: StorageConfig; raw: JsonObject; }
export interface RecordingPatch { enabled?: boolean; segment_minutes?: number; }
export interface DetectionPatch {
  enabled?: boolean; categories?: string[]; threshold_seconds?: number; confidence?: number;
  sample_interval?: number; lost_tolerance_seconds?: number;
}
export interface ChannelPatch {
  id: number; name?: string; enabled?: boolean; width?: number; height?: number; fps?: number; preview_fps?: number;
  recording?: RecordingPatch; detection?: DetectionPatch; privacy?: PrivacyPatch;
}
export interface StoragePatch { target_id?: string; max_gb?: number; min_free_gb?: number; }
export interface ConfigChanges { channels?: ChannelPatch[]; storage?: StoragePatch; }
export interface SaveConfigResult { ok: boolean; config: RecorderConfig; restart_required: boolean; }
export interface DownloadResult { saved: boolean; uri: string; bytes: number; }

export function emptyStatus(): RecorderStatus {
  return { channels: [], system: { hostname: '', cpu_percent: NaN, temperature_c: NaN,
    memory: { used_bytes: NaN, total_bytes: NaN, available_bytes: NaN, used_percent: NaN } },
    storage: { target_id: '', label: '', free_bytes: NaN, total_bytes: NaN, used_bytes: NaN, error: '' },
    detector: { ready: false, model: '', backend: '', error: '' }, uptime_seconds: NaN };
}
