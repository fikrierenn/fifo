/* ============================================================
   BKM Maliyet — Global Interaktif JS
   ============================================================ */

(() => {
    'use strict';
    console.log('[BKM] app.js YUKLENDI v2');

    /* ---- 0. Dark Mode Init ---- */
    if (localStorage.getItem('theme') === 'dark') {
        document.documentElement.classList.add('dark');
    }
    // Sync icon visibility with current theme
    const isDark = document.documentElement.classList.contains('dark');
    document.querySelectorAll('[data-icon-moon]').forEach(el => { if (isDark) el.classList.add('hidden'); else el.classList.remove('hidden'); });
    document.querySelectorAll('[data-icon-sun]').forEach(el => { if (isDark) el.classList.remove('hidden'); else el.classList.add('hidden'); });

    /* ---- 1. Clickable Table Rows ---- */
    document.addEventListener('click', (e) => {
        const row = e.target.closest('tr[data-href]');
        if (!row) return;
        // Link veya button icindeyse birak
        if (e.target.closest('a, button')) return;
        window.location = row.dataset.href;
    });

    // Cursor style
    document.querySelectorAll('tr[data-href]').forEach(row => {
        row.classList.add('cursor-pointer');
        row.addEventListener('mouseenter', () => row.classList.add('bg-gray-50'));
        row.addEventListener('mouseleave', () => row.classList.remove('bg-gray-50'));
    });

    /* ---- 2. Global Utilities (once tanimla, sonra kullan) ---- */
    window.BKM = window.BKM || {};

    /* ---- 2b. Sidebar Urun Arama (Autocomplete) ---- */
    // NOT: BKM.urunAra asagida tanimlanir, sidebar init ondan sonra calisir
    // Sidebar init'i section 3a'ya tasindi

    // HTML escape
    BKM.escHtml = function(s) {
        const d = document.createElement('div');
        d.textContent = s || '';
        return d.innerHTML;
    };

    // Urun arama autocomplete utility
    // cfg: { inputId, resultsId, onSelect(urun), stkIdInputId?, onSubmit?(val), containerId? }
    BKM.urunAra = function(cfg) {
        const input = document.getElementById(cfg.inputId);
        const results = document.getElementById(cfg.resultsId);
        if (!input || !results) return;
        // Guard: eski listener'lari temizle, yenisini ekle
        if (input._urunAraAC) input._urunAraAC.abort();
        const ac = new AbortController();
        input._urunAraAC = ac;
        const sig = { signal: ac.signal };

        let debounceTimer = null;
        let activeIdx = -1;

        // Tiklayinca mevcut text'i sec (yeni arama kolayligi)
        input.addEventListener('focus', () => input.select(), sig);

        // Form submit (sidebar icin)
        if (cfg.onSubmit) {
            const form = input.closest('form');
            if (form) {
                form.addEventListener('submit', (e) => {
                    e.preventDefault();
                    const val = input.value.trim();
                    if (val) cfg.onSubmit(val);
                }, sig);
            }
        }

        input.addEventListener('input', () => {
            clearTimeout(debounceTimer);
            activeIdx = -1;
            const q = input.value.trim();
            if (q.length < 3) { results.classList.add('hidden'); results.innerHTML = ''; return; }
            debounceTimer = setTimeout(() => fetchUrunler(q), 300);
        }, sig);

        async function fetchUrunler(q) {
            try {
                const resp = await fetch(`/api/urun-ara?q=${encodeURIComponent(q)}`);
                if (!resp.ok) return;
                const items = await resp.json();
                if (items.length === 0) {
                    results.innerHTML = '<div class="px-3 py-2 text-xs text-[color:var(--muted)]">Sonuc bulunamadi</div>';
                    results.classList.remove('hidden');
                    return;
                }
                if (cfg.stkIdInputId) {
                    // Form modu: tiklayinca stkId input'a yaz
                    results.innerHTML = items.map(u => {
                        const detay = [u.markaAd, u.kategori].filter(Boolean).join(' · ');
                        return `<div data-stkid="${u.stkId}" class="flex items-center gap-2 px-3 py-2 text-xs hover:bg-[color:var(--accent)]/10 transition cursor-pointer border-b border-[color:var(--line)] last:border-b-0">
                            <span class="font-medium text-[color:var(--accent)] shrink-0">${u.stkId}</span>
                            <span class="text-[color:var(--ink)] truncate">${BKM.escHtml(u.ad)}</span>
                            ${detay ? `<span class="text-[color:var(--muted)] shrink-0 text-[10px]">${BKM.escHtml(detay)}</span>` : ''}
                        </div>`;
                    }).join('');
                    results.classList.remove('hidden');
                    results.querySelectorAll('[data-stkid]').forEach(el => {
                        el.addEventListener('click', () => {
                            document.getElementById(cfg.stkIdInputId).value = el.dataset.stkid;
                            input.value = el.textContent.trim();
                            results.classList.add('hidden');
                            if (cfg.onSelect) cfg.onSelect({ stkId: parseInt(el.dataset.stkid, 10) });
                        });
                    });
                } else {
                    // Link modu: tiklayinca navigate
                    results.innerHTML = items.map((u, i) => {
                        const detay = [u.markaAd, u.kategori].filter(Boolean).join(' · ');
                        return `<a href="/Rapor/UrunDetay?stkId=${u.stkId}" data-idx="${i}" data-stkid="${u.stkId}" class="flex items-center gap-2 px-3 py-2 text-xs hover:bg-[color:var(--accent)]/10 transition cursor-pointer border-b border-[color:var(--line)] last:border-b-0">
                            <span class="font-medium text-[color:var(--accent)] shrink-0">${BKM.escHtml(u.kod)}</span>
                            <span class="text-[color:var(--ink)] truncate">${BKM.escHtml(u.ad)}</span>
                            ${detay ? `<span class="text-[color:var(--muted)] shrink-0 text-[10px]">${BKM.escHtml(detay)}</span>` : ''}
                        </a>`
                    }).join('');
                    results.classList.remove('hidden');
                    if (cfg.onSelect) {
                        results.querySelectorAll('a').forEach(el => {
                            el.addEventListener('click', (e) => {
                                e.preventDefault();
                                cfg.onSelect({ stkId: parseInt(el.dataset.stkid, 10) });
                            });
                        });
                    }
                }
            } catch { /* ignore */ }
        }

        // Klavye: yukari/asagi/enter
        input.addEventListener('keydown', (e) => {
            const els = results.querySelectorAll('a, [data-stkid]');
            if (!els.length) return;
            if (e.key === 'ArrowDown') { e.preventDefault(); activeIdx = Math.min(activeIdx + 1, els.length - 1); highlightItem(els); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); activeIdx = Math.max(activeIdx - 1, 0); highlightItem(els); }
            else if (e.key === 'Enter' && activeIdx >= 0) { e.preventDefault(); els[activeIdx].click(); }
            else if (e.key === 'Escape') { results.classList.add('hidden'); }
        }, sig);

        function highlightItem(els) {
            els.forEach((el, i) => {
                el.classList.toggle('bg-[color:var(--accent)]/10', i === activeIdx);
            });
        }

        // Disari tiklayinca kapat
        document.addEventListener('click', (e) => {
            const container = cfg.containerId ? document.getElementById(cfg.containerId) : input.parentElement;
            if (container && !container.contains(e.target)) results.classList.add('hidden');
        }, sig);
    };

    // Infinite scroll utility
    // cfg: { tbodyId, spinnerId, doneId, handlerName?, filterParams?, initialOffset, hasMore, renderRow(item), rowClass?, onRowCreated?(tr, r), shownCountId? }
    /* ---- 3a. Sidebar Urun Arama Init ---- */
    const searchForm = document.getElementById('sidebar-search');
    if (searchForm) {
        BKM.urunAra({
            inputId: 'sidebar-search-input',
            resultsId: 'sidebar-search-results',
            onSelect: u => window.location = '/Rapor/UrunDetay?stkId=' + u.stkId,
            onSubmit: val => window.location = `/Rapor/UrunDetay?stkId=${encodeURIComponent(val)}`,
            containerId: 'sidebar-search'
        });
    }

    // Infinite scroll utility
    BKM.infiniteScroll = function(cfg) {
        let offset = cfg.initialOffset || 0;
        let loading = false;
        let hasMore = cfg.hasMore !== false;
        const tbody = document.getElementById(cfg.tbodyId);
        const spinner = document.getElementById(cfg.spinnerId);
        const done = document.getElementById(cfg.doneId);
        const shownCount = cfg.shownCountId ? document.getElementById(cfg.shownCountId) : null;
        if (!tbody) return;

        const observer = new IntersectionObserver(entries => {
            if (entries[0].isIntersecting && !loading && hasMore) loadMore();
        }, { rootMargin: '200px' });

        function observeLast() {
            const rows = tbody.querySelectorAll('tr');
            if (rows.length && hasMore) observer.observe(rows[rows.length - 1]);
        }
        observeLast();

        async function loadMore() {
            loading = true;
            if (spinner) spinner.classList.remove('hidden');
            try {
                const params = cfg.filterParams ? `&${cfg.filterParams}` : '';
                const resp = await fetch(`?handler=${cfg.handlerName || 'More'}&offset=${offset}${params}`);
                const data = await resp.json();
                data.rows.forEach(r => {
                    const tr = document.createElement('tr');
                    tr.className = cfg.rowClass || 'hover:bg-gray-50 transition';
                    tr.innerHTML = cfg.renderRow(r);
                    if (r.stkId) {
                        tr.setAttribute('data-stkid', r.stkId);
                        tr.setAttribute('data-href', `/Rapor/UrunDetay?stkId=${r.stkId}`);
                    }
                    if (r.devreDisi) tr.classList.add('devre-disi');
                    if (cfg.onRowCreated) cfg.onRowCreated(tr, r);
                    tbody.appendChild(tr);
                });
                offset += data.rows.length;
                hasMore = data.hasMore;
                if (shownCount) shownCount.textContent = offset;
            } catch(e) { console.error('InfiniteScroll error:', e); }
            loading = false;
            if (spinner) spinner.classList.add('hidden');
            if (!hasMore && done) done.classList.remove('hidden');
            else observeLast();
        }

        return { loadMore, getOffset: () => offset };
    };

    /* ---- 3b. Chart Helpers ---- */

    // Doughnut chart
    BKM.doughnut = (canvasId, labels, data, colors) => {
        const ctx = document.getElementById(canvasId);
        if (!ctx || typeof Chart === 'undefined') return null;
        return new Chart(ctx, {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{
                    data,
                    backgroundColor: colors || [
                        '#3b82f6', '#10b981', '#f59e0b', '#8b5cf6',
                        '#ef4444', '#06b6d4', '#ec4899', '#6b7280'
                    ],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'bottom', labels: { padding: 16, usePointStyle: true, pointStyleWidth: 8 } }
                },
                cutout: '65%'
            }
        });
    };

    // Bar chart
    BKM.bar = (canvasId, labels, datasets) => {
        const ctx = document.getElementById(canvasId);
        if (!ctx || typeof Chart === 'undefined') return null;
        return new Chart(ctx, {
            type: 'bar',
            data: { labels, datasets },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { position: 'bottom', labels: { padding: 16, usePointStyle: true } } },
                scales: {
                    x: { grid: { display: false } },
                    y: { beginAtZero: true, ticks: { callback: v => v.toLocaleString('tr-TR') } }
                }
            }
        });
    };

    // Line chart
    BKM.line = (canvasId, labels, datasets) => {
        const ctx = document.getElementById(canvasId);
        if (!ctx || typeof Chart === 'undefined') return null;
        return new Chart(ctx, {
            type: 'line',
            data: { labels, datasets },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { position: 'bottom', labels: { padding: 16, usePointStyle: true } } },
                scales: {
                    x: { grid: { display: false } },
                    y: { beginAtZero: false, ticks: { callback: v => v.toLocaleString('tr-TR') } }
                },
                elements: { line: { tension: 0.3 }, point: { radius: 4, hoverRadius: 6 } }
            }
        });
    };

    /* ---- 4. Devre Disi Utility (Global) ---- */
    // CSS
    const ddStyle = document.createElement('style');
    ddStyle.textContent = `
        tr.devre-disi td { opacity: 0.45; text-decoration: line-through; }
        tr.devre-disi:hover td { opacity: 0.65; }
    `;
    document.head.appendChild(ddStyle);

    // Sebep secim modali (tek instance, her yerden kullanilir)
    const ddModal = document.createElement('div');
    ddModal.id = 'dd-modal';
    ddModal.className = 'fixed inset-0 z-[10000] hidden flex items-center justify-center bg-black/40';
    ddModal.innerHTML = `
        <div class="bg-white dark:bg-gray-800 rounded-xl shadow-2xl border border-[color:var(--line)] w-96 p-5">
            <h3 class="text-sm font-semibold mb-3 text-[color:var(--ink)]" id="dd-modal-title">Devre Disi Birakma Sebebi</h3>
            <div class="space-y-2 mb-3" id="dd-reasons">
                <label class="flex items-center gap-2 text-xs cursor-pointer"><input type="radio" name="dd-reason" value="Satis disi urun" checked class="accent-orange-500"> Satış dışı ürün</label>
                <label class="flex items-center gap-2 text-xs cursor-pointer"><input type="radio" name="dd-reason" value="Numune / Hediye urun" class="accent-orange-500"> Numune / Hediye ürün</label>
                <label class="flex items-center gap-2 text-xs cursor-pointer"><input type="radio" name="dd-reason" value="Stok hatasi / Yanlis kayit" class="accent-orange-500"> Stok hatası / Yanlış kayıt</label>
                <label class="flex items-center gap-2 text-xs cursor-pointer"><input type="radio" name="dd-reason" value="Dusuk degerli urun" class="accent-orange-500"> Düşük değerli ürün</label>
                <label class="flex items-center gap-2 text-xs cursor-pointer"><input type="radio" name="dd-reason" value="" class="accent-orange-500"> Diğer (manuel gir)</label>
            </div>
            <input type="text" id="dd-custom" class="w-full hidden rounded-lg border border-[color:var(--line)] bg-[color:var(--bg)] px-3 py-2 text-xs mb-3" placeholder="Sebebi yazin...">
            <div class="flex gap-2 justify-end">
                <button id="dd-cancel" class="px-4 py-1.5 text-xs rounded-lg border border-[color:var(--line)] hover:bg-gray-100 dark:hover:bg-gray-700 transition">Iptal</button>
                <button id="dd-confirm" class="px-4 py-1.5 text-xs rounded-lg bg-red-600 text-white hover:bg-red-700 transition font-medium">Devre Disi Birak</button>
            </div>
        </div>
    `;
    document.body.appendChild(ddModal);

    // Diger secilince custom input goster
    ddModal.querySelectorAll('input[name="dd-reason"]').forEach(r => {
        r.addEventListener('change', () => {
            document.getElementById('dd-custom').classList.toggle('hidden', r.value !== '');
        });
    });

    // Callback storage
    let _ddCallback = null;

    document.getElementById('dd-cancel').addEventListener('click', () => {
        ddModal.classList.add('hidden');
        _ddCallback = null;
    });

    document.getElementById('dd-confirm').addEventListener('click', () => {
        const selected = ddModal.querySelector('input[name="dd-reason"]:checked');
        let sebep = selected ? selected.value : '';
        if (!sebep) sebep = document.getElementById('dd-custom').value.trim();
        ddModal.classList.add('hidden');
        if (_ddCallback) _ddCallback(sebep || 'Belirtilmedi');
        _ddCallback = null;
    });

    // ── BKM.dd — Global Devre Disi API ──
    BKM.dd = {
        // Sebep modal ac, callback ile sebep dondur
        askSebep(title) {
            return new Promise((resolve) => {
                if (title) document.getElementById('dd-modal-title').textContent = title;
                document.getElementById('dd-custom').value = '';
                document.getElementById('dd-custom').classList.add('hidden');
                ddModal.querySelectorAll('input[name="dd-reason"]')[0].checked = true;
                _ddCallback = resolve;
                ddModal.classList.remove('hidden');
            });
        },

        // Tek urun devre disi birak (modal ile sebep sor)
        async ekle(stkId, sebepOrNull) {
            const sebep = sebepOrNull ?? await BKM.dd.askSebep();
            if (!sebep) return false;
            try {
                const resp = await fetch(`/api/devredisi/ekle?stkId=${stkId}&sebep=${encodeURIComponent(sebep)}`, { method: 'POST' });
                if (resp.ok) { BKM.dd._updateRows(stkId, true); return true; }
            } catch {}
            alert('Islem basarisiz.');
            return false;
        },

        // Tek urun aktif et
        async kaldir(stkId) {
            try {
                const resp = await fetch(`/api/devredisi/kaldir?stkId=${stkId}`, { method: 'POST' });
                if (resp.ok) { BKM.dd._updateRows(stkId, false); return true; }
            } catch {}
            alert('Islem basarisiz.');
            return false;
        },

        // Toggle: duruma gore ekle veya kaldir
        async toggle(stkId, currentlyDD) {
            if (currentlyDD) return await BKM.dd.kaldir(stkId);
            else return await BKM.dd.ekle(stkId);
        },

        // Toplu islem (stkIds array)
        async toplu(stkIds, islem, sebepOrNull) {
            if (!stkIds.length) { alert('Urun secin.'); return false; }
            let sebep = 'Toplu islem';
            if (islem === 'ekle') {
                sebep = sebepOrNull ?? await BKM.dd.askSebep(`${stkIds.length} urun icin sebep secin`);
                if (!sebep) return false;
            }
            if (!confirm(`${stkIds.length} urunu ${islem === 'ekle' ? 'devre disi birak' : 'aktif et'}mak istediginize emin misiniz?`)) return false;
            try {
                const resp = await fetch('/api/devredisi/toplu', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ stkIds, islem, sebep })
                });
                const data = await resp.json();
                if (data.ok) {
                    stkIds.forEach(id => BKM.dd._updateRows(id, islem === 'ekle'));
                    return data.etkilenen;
                }
            } catch {}
            alert('Islem basarisiz.');
            return false;
        },

        // Checkbox tabanlı toplu islem (kategori paneli icin)
        async topluFromCheckboxes(prefix, islem) {
            const cbs = document.querySelectorAll(`#kat-${prefix}-tbody .kat-cb:checked`);
            if (!cbs.length) { alert('Urun secin.'); return; }
            const stkIds = [...cbs].map(cb => parseInt(cb.value, 10));
            const result = await BKM.dd.toplu(stkIds, islem);
            if (result !== false) {
                cbs.forEach(cb => {
                    const tr = cb.closest('tr');
                    const durumTd = tr.querySelector('td:last-child');
                    const kodTd = tr.querySelectorAll('td')[1];
                    const adTd = tr.querySelectorAll('td')[2];
                    if (islem === 'ekle') {
                        tr.classList.add('bg-red-50/50', 'dark:bg-red-900/10');
                        kodTd.classList.add('line-through', 'opacity-50');
                        adTd.classList.add('line-through', 'opacity-50');
                        durumTd.innerHTML = '<span class="inline-block px-1.5 py-0.5 rounded bg-red-100 text-red-700 text-[10px] font-medium dark:bg-red-900/30 dark:text-red-400">Pasif</span>';
                    } else {
                        tr.classList.remove('bg-red-50/50', 'dark:bg-red-900/10');
                        kodTd.classList.remove('line-through', 'opacity-50');
                        adTd.classList.remove('line-through', 'opacity-50');
                        durumTd.innerHTML = '<span class="inline-block px-1.5 py-0.5 rounded bg-green-100 text-green-700 text-[10px] font-medium dark:bg-green-900/30 dark:text-green-400">Aktif</span>';
                    }
                    cb.checked = false;
                });
                document.getElementById(`kat-${prefix}-selcount`).textContent = '';
                document.getElementById(`kat-${prefix}-selall`).checked = false;
                alert(`${result} urun guncellendi.`);
            }
        },

        // Sayfa icindeki tum satirlari guncelle
        _updateRows(stkId, devreDisi) {
            document.querySelectorAll(`tr[data-stkid="${stkId}"]`).forEach(r => {
                if (devreDisi) r.classList.add('devre-disi');
                else r.classList.remove('devre-disi');
            });
        }
    };

    // ── Context Menu (Sag Tik) ──
    (() => {
        const menu = document.createElement('div');
        menu.id = 'ctx-menu';
        menu.className = 'fixed z-[9999] hidden min-w-[200px] rounded-lg border border-[color:var(--line)] bg-white shadow-xl py-1 text-sm dark:bg-gray-800 dark:border-gray-700';
        menu.innerHTML = `
            <a id="ctx-detay" href="#" class="flex items-center gap-2 px-4 py-2 text-[color:var(--ink)] hover:bg-[color:var(--accent)]/10 transition">
                <svg class="w-4 h-4 text-[color:var(--muted)]" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"/></svg>
                Urun Detayi Ac
            </a>
            <div id="ctx-toggle" class="flex items-center gap-2 px-4 py-2 cursor-pointer text-[color:var(--ink)] hover:bg-[color:var(--accent)]/10 transition">
                <svg class="w-4 h-4 text-[color:var(--muted)]" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636"/></svg>
                <span id="ctx-toggle-text">Devre Disi Birak</span>
            </div>
        `;
        document.body.appendChild(menu);

        let activeStkId = null;
        let activeRow = null;

        document.addEventListener('contextmenu', (e) => {
            const row = e.target.closest('tr[data-stkid]');
            if (!row) { menu.classList.add('hidden'); return; }
            e.preventDefault();
            activeStkId = parseInt(row.dataset.stkid, 10);
            activeRow = row;
            document.getElementById('ctx-detay').href = '/Rapor/UrunDetay?stkId=' + activeStkId;
            const isDD = row.classList.contains('devre-disi');
            document.getElementById('ctx-toggle-text').textContent = isDD ? 'Aktif Yap' : 'Devre Disi Birak';
            const x = Math.min(e.clientX, window.innerWidth - 220);
            const y = Math.min(e.clientY, window.innerHeight - 100);
            menu.style.left = x + 'px';
            menu.style.top = y + 'px';
            menu.classList.remove('hidden');
        });

        document.addEventListener('click', () => menu.classList.add('hidden'));
        document.addEventListener('scroll', () => menu.classList.add('hidden'), true);

        document.getElementById('ctx-toggle').addEventListener('click', async () => {
            if (!activeStkId) return;
            menu.classList.add('hidden');
            const isDD = activeRow && activeRow.classList.contains('devre-disi');
            await BKM.dd.toggle(activeStkId, isDD);
        });
    })();

    /* ---- 5b. UrunDetay Arama Autocomplete (otomatik init) ---- */
    // urunAraInput elementi varsa autocomplete baslatilir
    console.log('[BKM] UrunDetay autocomplete check:', !!document.getElementById('urunAraInput'));
    if (document.getElementById('urunAraInput')) {
        console.log('[BKM] UrunDetay autocomplete BASLATILIYOR');
        BKM.urunAra({
            inputId: 'urunAraInput',
            resultsId: 'urunAraResults',
            containerId: 'urunAraContainer',
            stkIdInputId: 'stkIdHidden',
            onSelect(item) {
                document.getElementById('stkIdHidden').value = item.stkId;
                document.getElementById('urunAraForm').submit();
            }
        });
        // StkId direkt girilirse (sayi + enter)
        document.getElementById('urunAraInput').addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                const val = e.target.value.trim();
                if (/^\d+$/.test(val)) document.getElementById('stkIdHidden').value = val;
            }
        });
    }

    /* ---- 6. Client-Side Sayfalama ---- */
    // data-paginate="50" olan tbody'lere otomatik sayfalama uygula
    // Sayfa boyutu attribute'den alinir (varsayilan: 50)
    document.querySelectorAll('tbody[data-paginate]').forEach(tbody => {
        const perPage = parseInt(tbody.dataset.paginate) || 50;
        const rows = Array.from(tbody.querySelectorAll('tr'));
        if (rows.length <= perPage) return;

        let page = 0;
        const totalPages = Math.ceil(rows.length / perPage);

        const nav = document.createElement('div');
        nav.className = 'flex items-center justify-between px-5 py-3 border-t border-[color:var(--line)] text-xs';
        nav.innerHTML = `
            <span class="text-[color:var(--muted)]" data-pg-info></span>
            <div class="flex gap-1">
                <button data-pg-prev class="rounded border border-[color:var(--line)] px-3 py-1.5 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed transition">&larr; Onceki</button>
                <button data-pg-next class="rounded border border-[color:var(--line)] px-3 py-1.5 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed transition">Sonraki &rarr;</button>
            </div>`;
        tbody.closest('table').parentElement.after(nav);

        const info = nav.querySelector('[data-pg-info]');
        const prevBtn = nav.querySelector('[data-pg-prev]');
        const nextBtn = nav.querySelector('[data-pg-next]');

        function render() {
            const start = page * perPage;
            const end = Math.min(start + perPage, rows.length);
            rows.forEach((r, i) => r.style.display = (i >= start && i < end) ? '' : 'none');
            info.textContent = `${start + 1}-${end} / ${rows.length} kayit (Sayfa ${page + 1}/${totalPages})`;
            prevBtn.disabled = page === 0;
            nextBtn.disabled = page >= totalPages - 1;
        }

        prevBtn.addEventListener('click', () => { if (page > 0) { page--; render(); } });
        nextBtn.addEventListener('click', () => { if (page < totalPages - 1) { page++; render(); } });
        render();
    });

    /* ---- 7. Tooltips (title-based, native) ---- */
    // KaynakTip açıklamaları
    const kaynakTipAciklama = {
        'ACILIS': 'Dönem başı açılış envanterinden oluşturulan katman',
        'FATURA': 'Alış faturasından oluşturulan katman',
        'ACILIS_TAMAMLA': 'Açılışta alış bulunamayan ürün için fallback fiyatla oluşturulan',
        'AYLIK_DEVIR': 'Önceki aydan devir edilen katman',
        'SENTETIK_ALIS': 'Stok yetersizliği için hayali katman'
    };

    const durumAciklama = {
        'NORMAL': 'Gerçek fatura fiyatıyla oluşturulmuş',
        'TAMAMLAMA': 'Son alış fiyatıyla tamamlanmış',
        'MERKEZ_TAMAMLAMA': 'Merkez depo fiyatıyla tamamlanmış',
        'SART_TAMAMLAMA': 'Son geçerli satış fiyatıyla',
        'FIYAT_YOK': 'Hiçbir kaynak fiyat bulunamadı',
        'HAYALI_SART': 'Sentetik — fallback tablosundan',
        'HAYALI_SABIT': 'Sentetik — sabit parametre ile',
        'SABIT_FIYAT_TAMAMLAMA': 'Sabit fallback fiyat uygulandı'
    };

    document.querySelectorAll('[data-tip-kaynak]').forEach(el => {
        const tip = el.dataset.tipKaynak;
        if (kaynakTipAciklama[tip]) el.title = kaynakTipAciklama[tip];
    });

    document.querySelectorAll('[data-tip-durum]').forEach(el => {
        const tip = el.dataset.tipDurum;
        if (durumAciklama[tip]) el.title = durumAciklama[tip];
    });

})();
