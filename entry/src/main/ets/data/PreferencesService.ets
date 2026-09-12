import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppearanceMode, ClientPreferences } from '../model/Models';
import { DEFAULT_ENDPOINT, normalizeEndpoint } from './RecorderApi';

/** 手机端偏好与开发板设置分离，换地址或主题不会向板端发送 PUT。 */
export class PreferencesService {
  static async load(context: common.UIAbilityContext): Promise<ClientPreferences> {
    const store = await preferences.getPreferences(context, { name: 'recorder_client' });
    const saved = store.getSync('endpoint', DEFAULT_ENDPOINT) as string;
    let endpoint = DEFAULT_ENDPOINT;
    try { endpoint = normalizeEndpoint(saved); } catch (_) { /* 无效旧值回到默认地址。 */ }
    const mode = store.getSync('appearance', 'light') as string;
    const appearance: AppearanceMode = mode === 'dark' ? 'dark' : mode === 'system' ? 'system' : 'light';
    return { endpoint: endpoint, appearance: appearance };
  }
  static async saveEndpoint(context: common.UIAbilityContext, value: string): Promise<void> {
    const endpoint = normalizeEndpoint(value);
    const store = await preferences.getPreferences(context, { name: 'recorder_client' });
    store.putSync('endpoint', endpoint); await store.flush();
  }
  static async saveAppearance(context: common.UIAbilityContext, mode: AppearanceMode): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'recorder_client' });
    store.putSync('appearance', mode); await store.flush();
  }
}
