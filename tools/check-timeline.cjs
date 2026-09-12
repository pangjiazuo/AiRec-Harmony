/* 无设备的时间轴纯逻辑检查；原生 ArkTS/Video 验证仍需单独执行。 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const deveco = process.env.DEVECO_HOME || 'C:/Program Files/Huawei/DevEco Studio';
const ts = require(path.join(deveco, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const project = path.resolve(__dirname, '..');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'recorder-timeline-'));
const files = ['model/Models', 'model/Timeline', 'data/JsonCodec', 'data/TimelineCodec', 'data/TimelineChecks'];
try {
  for (const name of files) {
    const source = fs.readFileSync(path.join(project, 'entry/src/main/ets', `${name}.ets`), 'utf8');
    const compiled = ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
    }}).outputText;
    const target = path.join(scratch, `${name}.js`);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, compiled);
  }
  const all = [];
  const { runTimelineChecks } = require(path.join(scratch, 'data/TimelineChecks.js'));
  for (const zone of ['Asia/Shanghai', 'America/New_York', 'Europe/Berlin']) {
    process.env.TZ = zone;
    all.push({ zone, checks: runTimelineChecks() });
  }
  console.log(JSON.stringify(all, null, 2));
  if (all.some(group => group.checks.some(check => !check.passed))) process.exitCode = 1;
} finally {
  // mkdtemp 直接生成的本轮专用临时目录，不引用其他工程。
  const tempRoot = path.resolve(os.tmpdir()) + path.sep;
  if (!path.resolve(scratch).startsWith(tempRoot) || !path.basename(scratch).startsWith('recorder-timeline-')) {
    throw new Error('临时检查目录越界，保留现场');
  }
  fs.rmSync(scratch, { recursive: true, force: true });
}
