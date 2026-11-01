/* 文档网页的交互：视图切换、折叠段、行筛选、待确认清单、指令框复制、打印前展开。 */
(function () {
  function all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  // 视图切换：.view-switch 内的按钮控制同一父节点下的 .view
  all('.view-switch').forEach(function (group) {
    var host = group.parentNode;
    all('.seg', group).forEach(function (btn) {
      btn.addEventListener('click', function () {
        all('.seg', group).forEach(function (b) { b.setAttribute('aria-pressed', String(b === btn)); });
        all('.view', host).forEach(function (v) { v.hidden = v.getAttribute('data-view') !== btn.getAttribute('data-view'); });
      });
    });
  });

  // 全部场景一起切换视图：data-all="lane|table"
  all('[data-all]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var view = btn.getAttribute('data-all');
      all('.seg', btn.parentNode).forEach(function (b) { b.setAttribute('aria-pressed', String(b === btn)); });
      all('details.fold').forEach(function (d) {
        all('.view', d).forEach(function (v) { v.hidden = v.getAttribute('data-view') !== view; });
        all('.view-switch .seg', d).forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-view') === view)); });
      });
    });
  });

  // 折叠段：data-fold="open|close" 的按钮控制全部 details.fold
  all('[data-fold]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var open = btn.getAttribute('data-fold') === 'open';
      all('details.fold').forEach(function (d) { d.open = open; });
    });
  });

  // 行筛选：.segs[data-filter="表格id"] 的按钮按 data-key 过滤 tr[data-key]
  all('.segs[data-filter]').forEach(function (group) {
    var table = document.getElementById(group.getAttribute('data-filter'));
    if (!table) return;
    all('.seg', group).forEach(function (btn) {
      btn.addEventListener('click', function () {
        var key = btn.getAttribute('data-key');
        all('.seg', group).forEach(function (b) { b.setAttribute('aria-pressed', String(b === btn)); });
        all('tbody tr[data-key]', table).forEach(function (tr) { tr.hidden = key !== 'all' && tr.getAttribute('data-key') !== key; });
      });
    });
  });

  // 待确认清单：勾选状态只存在本机浏览器
  all('ul.qs[data-store]').forEach(function (list) {
    var storeKey = list.getAttribute('data-store');
    var boxes = all('input[type="checkbox"]', list);
    var bar = document.querySelector('[data-prog="' + list.id + '"] .prog-bar span');
    var label = document.querySelector('[data-prog="' + list.id + '"] .prog-n');
    var saved = {};
    try { saved = JSON.parse(localStorage.getItem(storeKey) || '{}') || {}; } catch (e) { saved = {}; }
    function update() {
      var done = boxes.filter(function (b) { return b.checked; }).length;
      if (bar) bar.style.width = (boxes.length ? done / boxes.length * 100 : 0) + '%';
      if (label) label.textContent = done + ' / ' + boxes.length;
    }
    boxes.forEach(function (b) {
      b.checked = !!saved[b.id];
      b.addEventListener('change', function () {
        saved[b.id] = b.checked;
        try { localStorage.setItem(storeKey, JSON.stringify(saved)); } catch (e) {}
        update();
      });
    });
    var clear = document.querySelector('[data-clear="' + list.id + '"]');
    if (clear) clear.addEventListener('click', function () {
      boxes.forEach(function (b) { b.checked = false; saved[b.id] = false; });
      try { localStorage.removeItem(storeKey); } catch (e) {}
      update();
    });
    update();
  });

  // 清单按答复方筛选：.segs[data-filter-list="清单id"]
  all('.segs[data-filter-list]').forEach(function (group) {
    var list = document.getElementById(group.getAttribute('data-filter-list'));
    if (!list) return;
    all('.seg', group).forEach(function (btn) {
      btn.addEventListener('click', function () {
        var key = btn.getAttribute('data-key');
        all('.seg', group).forEach(function (b) { b.setAttribute('aria-pressed', String(b === btn)); });
        all('li[data-key]', list).forEach(function (li) { li.hidden = key !== 'all' && li.getAttribute('data-key') !== key; });
      });
    });
  });

  // 指令框：复制全文按钮
  all('.cmd').forEach(function (box) {
    var btn = box.querySelector('.cmd-copy'), pre = box.querySelector('pre');
    if (!btn || !pre) return;
    btn.addEventListener('click', function () {
      var text = pre.innerText;
      var done = function () { btn.textContent = '已复制'; setTimeout(function () { btn.textContent = '复制全文'; }, 1600); };
      var fallback = function () {
        var range = document.createRange(); range.selectNodeContents(pre);
        var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
        try { document.execCommand('copy'); done(); } catch (e) { btn.textContent = '已选中，请按复制键'; }
      };
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(done, fallback); } else { fallback(); }
      } catch (e) { fallback(); }
    });
  });

  // 打印前展开全部折叠段并显示全部视图
  window.addEventListener('beforeprint', function () {
    all('details.fold').forEach(function (d) { d.open = true; });
    all('.view').forEach(function (v) { v.hidden = false; });
  });
})();
