/* I1 定向回归：仅操作实际交付 JSON 的内存副本，不写研究数据或执行查询。 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { createHash, webcrypto } = require('node:crypto');
if (!globalThis.crypto) globalThis.crypto = webcrypto;
const C = require('./workbench-core.js');
const inputPath = path.join(__dirname, 'SK-BEH-001.json');
const configPath = path.resolve(__dirname, '../../02_工作区/Matt执行/run-config.json');
const inputBytes = fs.readFileSync(inputPath);
const configBytes = fs.readFileSync(configPath);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const config = JSON.parse(configBytes);
const actor = { actor_type: 'controller_delegate', actor_label: 'I1 自动回归内存副本，非真实审阅' };
const allIds = d => [...C.collections.flatMap(k => d[k].map(x => x.id)),
  ...(d.historical_decisions || []).map(x => x.id)];
const assertUnique = d => assert.equal(new Set(allIds(d)).size, allIds(d).length, '当前与历史 ID 不得重名');
// 历史冻结的外层状态会按既有规则失效；原始审计载荷及其他元数据必须保留。
const historySnapshots = d => d.snapshots.filter(s => s.audit_origin === 'external_history').map(s => {
  const original = C.copy(s);
  delete original.status;
  delete original.invalidation_reason;
  return original;
});
async function assertValid(d, label) {
  const result = await C.audit(d, config);
  assert.deepEqual(result.errors, [], label + ' audit');
  assert.deepEqual(result.stale, [], label + ' stale');
  assert.deepEqual(C.validate(d, config), [], label + ' validate');
  assertUnique(d);
}

(async () => {
  assert(await C.verifyPolicy(config), '唯一运行参数哈希');
  let doc = JSON.parse(inputBytes);
  assert.equal(doc.run_id, 'SK-BEH-001');
  assert(doc.historical_decisions.length > 0, '缺陷夹具必须含历史决定');
  const oldHistory = C.canonical(doc.historical_decisions);
  const oldSnapshots = C.canonical(historySnapshots(doc));
  const originalIds = new Set(allIds(doc));
  const decisionCount = doc.decisions.length;
  const snapshotCount = doc.snapshots.length;
  await assertValid(doc, '导入实际 BEH');
  for (const kind of ['review', 'direction', 'package']) assert.equal(C.latest(doc, kind), undefined, '历史冻结不能代替本轮冻结');
  assert.equal(C.base(doc, 'D').id, 'SK-BEH-001-D013', '必须避开历史 D001–D006 和当前 D007–D012');

  // 对齐应用 change()：复制、操作、audit，通过后才替换当前记录。
  async function change(fn, label) {
    const next = C.copy(doc);
    await fn(next);
    await assertValid(next, label);
    doc = next;
  }
  await change(d => C.saveReview(d, config, d.branches.map(b => ({
    branch_id: b.id, action: 'gap', reason: '自动回归内存副本：保留缺口，不形成真实审阅决定', required_changes: null,
  })), actor), '逐支保存审阅');
  const newReviews = doc.decisions.slice(decisionCount);
  assert.equal(newReviews.length, doc.branches.length);
  assert(newReviews.every(x => !originalIds.has(x.id)));
  await change(d => C.snapshot(d, config, 'review', actor), '审阅冻结');
  await change(d => C.makeCandidates(d), '方向草案');
  const candidate = doc.candidates.find(x => x.input_revision === doc.revision && !x.invalidated);
  assert(candidate);
  assert.equal(C.gates(doc, candidate, config).formal, false, '仍不能正式通过');
  await change(d => C.snapshot(d, config, 'direction', actor, {
    candidate_id: candidate.id, classification: 'trial_with_gaps', reason: '自动回归内存副本：仅验证含缺口试运行冻结',
  }), '方向冻结');
  await change(d => C.snapshot(d, config, 'package', actor), '最终包冻结');
  const packageId = C.latest(doc, 'package').id;
  const exported = JSON.stringify(doc);
  doc = JSON.parse(exported);
  await assertValid(doc, '导出后重导入');
  for (const kind of ['review', 'direction', 'package']) assert(C.latest(doc, kind));
  assert.equal(C.latest(doc, 'package').id, packageId);
  assert.equal(C.latest(doc, 'package').classification, 'trial_with_gaps');
  assert.equal(C.gates(doc, doc.candidates.find(x => x.id === candidate.id), config).formal, false);
  assert.equal(C.canonical(doc.historical_decisions), oldHistory, '历史决定保持原样');
  assert.equal(C.canonical(historySnapshots(doc)), oldSnapshots, '历史原始审计载荷保持原样');
  assert.deepEqual(fs.readFileSync(inputPath), inputBytes, '交付研究 JSON 未修改');
  assert.deepEqual(fs.readFileSync(configPath), configBytes, '运行参数未修改');
  const newDecisions = doc.decisions.slice(decisionCount);
  const newSnapshots = doc.snapshots.slice(snapshotCount);
  assert(newDecisions.every(x => !originalIds.has(x.id)));
  assert(newSnapshots.every(x => !originalIds.has(x.id)));
  console.log(JSON.stringify({
    check: 'I1 actual BEH import-review-freezes-export-reimport', status: 'passed',
    input_sha256: hash(inputBytes), config_file_sha256: hash(configBytes),
    core_sha256: hash(fs.readFileSync(path.join(__dirname, 'workbench-core.js'))),
    test_sha256: hash(fs.readFileSync(__filename)),
    new_decision_ids: newDecisions.map(x => x.id), new_snapshot_ids: newSnapshots.map(x => x.id),
    historical_decisions_preserved: doc.historical_decisions.length,
    historical_payloads_preserved: historySnapshots(doc).length,
    ids_unique: true, original_files_unchanged: true,
    package_classification: C.latest(doc, 'package').classification,
    formal_gate_passed: false, research_writes: 0,
  }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
