// Local stand-in for a model so the AI patterns (rules/8-AI协作.md) can be shown without any network call.
// Products replace simulateStream with their own service; the Aham Design components only need an async iterable
// of text that stops when the signal aborts. All texts below are fictional.
export async function* simulateStream(text, { signal, delay = 40, failAfter = null } = {}) {
  const parts = text.match(/[^，。；\n]+[，。；]?|\n+/g) ?? [text];
  let sent = 0;
  for (const part of parts) {
    await new Promise(resolve => {
      const timer = setTimeout(resolve, delay);
      signal?.addEventListener('abort', () => { clearTimeout(timer); resolve(); }, { once: true });
    });
    if (signal?.aborted) return;
    if (failAfter !== null && sent >= failAfter) throw new Error('AI 服务暂时不可用（示例模拟）。');
    sent++;
    yield part;
  }
}

// Waits until aborted: keeps a block in the generating state for the state preview.
export async function* holdStream(text, { signal } = {}) {
  yield text;
  await new Promise(resolve => signal?.addEventListener('abort', resolve, { once: true }));
}

// A project moves from 未开始 to 进行中 once the kick-off meeting is agreed; 已完成 and 已暂停 are set by people, not AI advice.
export const nextStatus = current => current === '未开始' ? '进行中' : current;

export function summaryText(record) {
  return `${record.name}项目状态是「${record.status}」，负责人${record.owner}。\n\n最近一次更新在 ${record.updated}：已约好下周二开工会，需要先确认供应商的安装方案。\n\n可以先发送安装方案模板，并在开工会前两天确认参会人员。`;
}

export function draftText() {
  return '今天与供应商确认了开工会安排，约定下周二在现场召开。\n\n待办：发送安装方案模板，确认参会人员和会议室。';
}

export function nextStepPlan(record) {
  const to = nextStatus(record.status), task = { key: 'task', target: '新建任务', to: '催交安装方案 · 截止 2026-10-06' };
  return to === record.status ? {
    text: '最近一次更新已约定开工会，供应商在准备安装方案。\n\n可以新建一个任务催交安装方案。',
    reason: '最近一次更新已约定开工会。',
    changes: [task],
  } : {
    text: `最近一次更新已约定开工会，供应商在准备安装方案。\n\n可以把项目状态改为「${to}」，并新建一个任务催交安装方案。`,
    reason: '最近一次更新已约定开工会。',
    changes: [{ key: 'status', target: '项目状态', from: record.status, to }, task],
  };
}
