const state = {
    isOpen: false,
    dashboard: null,
    charges: [],
    selectedCitizen: null,
    selectedReport: null,
    currentPage: 'dashboard'
};

const root = document.getElementById('mdtRoot');
const closeBtn = document.getElementById('closeMdt');
const refreshBtn = document.getElementById('refreshDashboard');
const navButtons = Array.from(document.querySelectorAll('.nav-btn'));

const pages = {
    dashboard: document.getElementById('page-dashboard'),
    citizens: document.getElementById('page-citizens'),
    vehicles: document.getElementById('page-vehicles'),
    reports: document.getElementById('page-reports'),
    warrants: document.getElementById('page-warrants'),
    bolos: document.getElementById('page-bolos'),
    evidence: document.getElementById('page-evidence'),
    radar: document.getElementById('page-radar'),
    officer: document.getElementById('page-officer')
};

const getResourceName = () => {
    if (typeof GetParentResourceName === 'function') {
        return GetParentResourceName();
    }
    return 'cbk-mdt';
};

const post = async (endpoint, payload) => {
    const response = await fetch(`https://${getResourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    });
    return response.json();
};

const request = async (action, payload = {}) => {
    const result = await post('mdt:request', { action, payload });
    if (!result.ok) {
        notify(result.data || 'Request failed', true);
        throw new Error(result.data || 'Request failed');
    }
    return result.data;
};

const appendActivity = async (action, details) => {
    await post('mdt:appendActivity', { action, details });
};

const notify = (text, isError = false) => {
    console[isError ? 'error' : 'log'](`[MDT] ${text}`);
};

const escapeHtml = (value) => {
    if (value === null || value === undefined) return '';
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
};

const setPage = (pageKey) => {
    state.currentPage = pageKey;
    Object.entries(pages).forEach(([key, element]) => {
        element.classList.toggle('active', key === pageKey);
    });

    navButtons.forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.page === pageKey);
    });
};

const renderDashboard = () => {
    const data = state.dashboard || { stats: {}, recentReports: [], myReports: [], officer: {} };
    pages.dashboard.innerHTML = `
        <div class="stats-grid">
            <div class="stat">
                <div class="muted">Open Warrants</div>
                <div class="stat-value">${Number(data.stats.openWarrants || 0)}</div>
            </div>
            <div class="stat">
                <div class="muted">Active BOLOs</div>
                <div class="stat-value">${Number(data.stats.activeBolos || 0)}</div>
            </div>
            <div class="stat">
                <div class="muted">Reports Today</div>
                <div class="stat-value">${Number(data.stats.reportsToday || 0)}</div>
            </div>
        </div>

        <div class="card">
            <div class="result-title">Recent Reports</div>
            <div class="results">
                ${(data.recentReports || []).map((report) => `
                    <div class="result-item">
                        <div class="result-title">#${report.id} ${escapeHtml(report.title)}</div>
                        <div class="muted">${escapeHtml(report.report_type)} | ${escapeHtml(report.officer_name)} | Fines: $${Number(report.total_fines || 0)} | Jail: ${Number(report.total_jail_time || 0)} min</div>
                    </div>
                `).join('') || '<div class="muted">No reports found.</div>'}
            </div>
        </div>

        <div class="card">
            <div class="result-title">Officer Snapshot</div>
            <div class="muted">${escapeHtml(data.officer.full_name || '')} | Callsign: ${escapeHtml(data.officer.callsign || 'N/A')} | Rank: ${escapeHtml(data.officer.rank_label || 'N/A')}</div>
        </div>
    `;
};

const renderCitizens = () => {
    pages.citizens.innerHTML = `
        <div class="card">
            <div class="row">
                <div class="field">
                    <label>Search Citizen</label>
                    <input id="citizenSearchInput" placeholder="Name, identifier, phone" />
                </div>
                <div class="field" style="justify-content:flex-end;">
                    <button id="citizenSearchBtn" class="btn">Search</button>
                </div>
            </div>
            <div id="citizenSearchResults" class="results" style="margin-top:10px;"></div>
        </div>
        <div id="citizenProfileWrap" class="card hidden"></div>
    `;

    document.getElementById('citizenSearchBtn').addEventListener('click', async () => {
        const query = document.getElementById('citizenSearchInput').value.trim();
        const rows = await request('search_citizens', { query });
        const container = document.getElementById('citizenSearchResults');

        container.innerHTML = rows.map((row) => `
            <div class="result-item">
                <div class="result-title">${escapeHtml(row.full_name)} (${escapeHtml(row.identifier)})</div>
                <div class="muted">DOB: ${escapeHtml(row.date_of_birth || 'N/A')} | Phone: ${escapeHtml(row.phone_number || 'N/A')}</div>
                <button class="btn citizen-open" data-id="${escapeHtml(row.identifier)}" style="margin-top:8px;">Open Profile</button>
            </div>
        `).join('') || '<div class="muted">No results.</div>';

        container.querySelectorAll('.citizen-open').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const identifier = btn.dataset.id;
                const profile = await request('get_citizen_profile', { identifier });
                state.selectedCitizen = profile.citizen;

                const profileWrap = document.getElementById('citizenProfileWrap');
                profileWrap.classList.remove('hidden');
                profileWrap.innerHTML = `
                    <div class="result-title">Citizen Profile: ${escapeHtml(profile.citizen.full_name)}</div>
                    <div class="muted">Identifier: ${escapeHtml(profile.citizen.identifier)} | DOB: ${escapeHtml(profile.citizen.date_of_birth || 'N/A')} | Phone: ${escapeHtml(profile.citizen.phone_number || 'N/A')}</div>
                    <div class="field" style="margin-top:10px;">
                        <label>Notes</label>
                        <textarea id="citizenNotes">${escapeHtml(profile.citizen.notes || '')}</textarea>
                    </div>
                    <button id="saveCitizenNotes" class="btn" style="margin-top:8px;">Save Notes</button>
                    <div class="result-title" style="margin-top:12px;">Criminal History</div>
                    <div class="results">
                        ${(profile.criminalHistory || []).map((r) => `
                            <div class="result-item">
                                <div class="result-title">#${r.id} ${escapeHtml(r.title)}</div>
                                <div class="muted">${escapeHtml(r.report_type)} | Fine: $${Number(r.total_fines || 0)} | Jail: ${Number(r.total_jail_time || 0)} min</div>
                            </div>
                        `).join('') || '<div class="muted">No criminal history entries.</div>'}
                    </div>
                `;

                document.getElementById('saveCitizenNotes').addEventListener('click', async () => {
                    await request('save_citizen_notes', {
                        identifier: profile.citizen.identifier,
                        notes: document.getElementById('citizenNotes').value,
                        flags: profile.citizen.flags || []
                    });
                    notify('Citizen notes saved.');
                });
            });
        });
    });
};

const renderVehicles = () => {
    pages.vehicles.innerHTML = `
        <div class="card">
            <div class="row">
                <div class="field">
                    <label>Search Vehicle</label>
                    <input id="vehicleSearchInput" placeholder="Plate or owner" />
                </div>
                <div class="field" style="justify-content:flex-end;">
                    <button id="vehicleSearchBtn" class="btn">Search</button>
                </div>
            </div>
            <div id="vehicleSearchResults" class="results" style="margin-top:10px;"></div>
        </div>
    `;

    document.getElementById('vehicleSearchBtn').addEventListener('click', async () => {
        const query = document.getElementById('vehicleSearchInput').value.trim();
        const rows = await request('search_vehicles', { query });
        const container = document.getElementById('vehicleSearchResults');

        container.innerHTML = rows.map((row) => `
            <div class="result-item">
                <div class="result-title">${escapeHtml(row.plate)} ${row.stolen === 1 ? '<span class="pill danger">STOLEN</span>' : '<span class="pill ok">CLEAR</span>'}</div>
                <div class="muted">Owner: ${escapeHtml(row.owner_name || row.owner_identifier || 'Unknown')} | ${escapeHtml(row.model_name || 'Unknown Model')} | ${escapeHtml(row.vehicle_class || '')}</div>
                <button class="btn toggle-stolen" data-plate="${escapeHtml(row.plate)}" data-stolen="${row.stolen === 1 ? '0' : '1'}" style="margin-top:8px;">${row.stolen === 1 ? 'Mark Clear' : 'Flag Stolen'}</button>
            </div>
        `).join('') || '<div class="muted">No results.</div>';

        container.querySelectorAll('.toggle-stolen').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const plate = btn.dataset.plate;
                const stolen = btn.dataset.stolen === '1';
                await request('set_vehicle_stolen', { plate, stolen, notes: stolen ? 'Flagged from MDT' : 'Cleared from MDT' });
                document.getElementById('vehicleSearchBtn').click();
            });
        });
    });
};

const renderReports = () => {
    pages.reports.innerHTML = `
        <div class="card">
            <div class="result-title">Create Incident / Arrest Report</div>
            <div class="row-3">
                <div class="field">
                    <label>Type</label>
                    <select id="reportType">
                        <option value="incident">Incident</option>
                        <option value="arrest">Arrest</option>
                    </select>
                </div>
                <div class="field">
                    <label>Title</label>
                    <input id="reportTitle" />
                </div>
                <div class="field">
                    <label>Summary</label>
                    <input id="reportSummary" />
                </div>
            </div>
            <div class="field" style="margin-top:10px;">
                <label>Narrative</label>
                <textarea id="reportNarrative"></textarea>
            </div>
            <div class="row">
                <div class="field">
                    <label>Involved Citizens (comma separated identifiers)</label>
                    <input id="reportCitizens" placeholder="CITIZENID1,CITIZENID2" />
                </div>
                <div class="field">
                    <label>Involved Vehicles (comma separated plates)</label>
                    <input id="reportVehicles" placeholder="ABC123,XYZ987" />
                </div>
            </div>
            <div class="field" style="margin-top:10px;">
                <label>Charges (format CODE:COUNT, e.g. PC200:1,PC101:2)</label>
                <input id="reportCharges" placeholder="PC200:1,PC101:2" />
            </div>
            <button id="createReportBtn" class="btn" style="margin-top:10px;">Create Report</button>
        </div>

        <div class="card">
            <div class="row">
                <div class="field">
                    <label>Search Reports</label>
                    <input id="reportSearchInput" placeholder="Title or officer" />
                </div>
                <div class="field" style="justify-content:flex-end;">
                    <button id="reportSearchBtn" class="btn">Search</button>
                </div>
            </div>
            <div id="reportSearchResults" class="results" style="margin-top:10px;"></div>
        </div>
    `;

    document.getElementById('createReportBtn').addEventListener('click', async () => {
        const parseCsv = (text) => text.split(',').map((x) => x.trim()).filter(Boolean);
        const parseCharges = (text) => parseCsv(text).map((entry) => {
            const [code, count] = entry.split(':');
            return { code: (code || '').trim(), count: Number(count || 1) };
        });

        const involvedCitizens = parseCsv(document.getElementById('reportCitizens').value).map((identifier) => ({ identifier }));
        const involvedVehicles = parseCsv(document.getElementById('reportVehicles').value).map((plate) => ({ plate }));

        const report = await request('create_report', {
            report_type: document.getElementById('reportType').value,
            title: document.getElementById('reportTitle').value,
            summary: document.getElementById('reportSummary').value,
            narrative: document.getElementById('reportNarrative').value,
            involved_citizens: involvedCitizens,
            involved_vehicles: involvedVehicles,
            charges: parseCharges(document.getElementById('reportCharges').value),
            evidence_refs: []
        });

        notify(`Report #${report.id} created. Fines: $${report.total_fines}, Jail: ${report.total_jail_time} min`);
        appendActivity('report_created_ui', `Created report #${report.id} from NUI`);
    });

    document.getElementById('reportSearchBtn').addEventListener('click', async () => {
        const rows = await request('search_reports', { query: document.getElementById('reportSearchInput').value.trim() });
        const container = document.getElementById('reportSearchResults');

        container.innerHTML = rows.map((r) => `
            <div class="result-item">
                <div class="result-title">#${r.id} ${escapeHtml(r.title)}</div>
                <div class="muted">${escapeHtml(r.report_type)} | ${escapeHtml(r.officer_name)} | Fine: $${Number(r.total_fines || 0)} | Jail: ${Number(r.total_jail_time || 0)} min</div>
            </div>
        `).join('') || '<div class="muted">No reports found.</div>';
    });
};

const renderWarrants = () => {
    pages.warrants.innerHTML = `
        <div class="card">
            <div class="result-title">Create Warrant</div>
            <div class="row-3">
                <div class="field"><label>Citizen Identifier</label><input id="warrantCitizen" /></div>
                <div class="field"><label>Title</label><input id="warrantTitle" /></div>
                <div class="field"><label>Reason</label><input id="warrantReason" /></div>
            </div>
            <button id="createWarrantBtn" class="btn" style="margin-top:10px;">Create Warrant</button>
        </div>
        <div class="card">
            <button id="refreshWarrants" class="btn">Refresh Warrants</button>
            <div id="warrantResults" class="results" style="margin-top:10px;"></div>
        </div>
    `;

    const refresh = async () => {
        const rows = await request('list_warrants', { status: 'active' });
        const container = document.getElementById('warrantResults');
        container.innerHTML = rows.map((w) => `
            <div class="result-item">
                <div class="result-title">#${w.id} ${escapeHtml(w.title)}</div>
                <div class="muted">Citizen: ${escapeHtml(w.citizen_name || w.citizen_identifier)} | Status: ${escapeHtml(w.status)} | Expires: ${escapeHtml(w.expires_at || 'N/A')}</div>
                <button class="btn warrant-serve" data-id="${w.id}" style="margin-top:8px;">Mark Served</button>
            </div>
        `).join('') || '<div class="muted">No warrants.</div>';

        container.querySelectorAll('.warrant-serve').forEach((btn) => {
            btn.addEventListener('click', async () => {
                await request('update_warrant_status', { id: Number(btn.dataset.id), status: 'served' });
                refresh();
            });
        });
    };

    document.getElementById('createWarrantBtn').addEventListener('click', async () => {
        await request('create_warrant', {
            citizen_identifier: document.getElementById('warrantCitizen').value,
            title: document.getElementById('warrantTitle').value,
            reason: document.getElementById('warrantReason').value
        });
        refresh();
    });

    document.getElementById('refreshWarrants').addEventListener('click', refresh);
    refresh();
};

const renderBolos = () => {
    pages.bolos.innerHTML = `
        <div class="card">
            <div class="result-title">Create BOLO</div>
            <div class="row-3">
                <div class="field">
                    <label>Type</label>
                    <select id="boloType">
                        <option value="person">Person</option>
                        <option value="vehicle">Vehicle</option>
                        <option value="general">General</option>
                    </select>
                </div>
                <div class="field"><label>Title</label><input id="boloTitle" /></div>
                <div class="field"><label>Description</label><input id="boloDescription" /></div>
            </div>
            <div class="row" style="margin-top:10px;">
                <div class="field"><label>Target Identifier</label><input id="boloIdentifier" /></div>
                <div class="field"><label>Target Plate</label><input id="boloPlate" /></div>
            </div>
            <button id="createBoloBtn" class="btn" style="margin-top:10px;">Create BOLO</button>
        </div>
        <div class="card">
            <button id="refreshBolos" class="btn">Refresh BOLOs</button>
            <div id="boloResults" class="results" style="margin-top:10px;"></div>
        </div>
    `;

    const refresh = async () => {
        const rows = await request('list_bolos', { status: 'active' });
        const container = document.getElementById('boloResults');
        container.innerHTML = rows.map((b) => `
            <div class="result-item">
                <div class="result-title">#${b.id} ${escapeHtml(b.title)}</div>
                <div class="muted">Type: ${escapeHtml(b.bolo_type)} | Status: ${escapeHtml(b.status)} | Target: ${escapeHtml(b.target_identifier || b.target_plate || 'N/A')}</div>
                <button class="btn bolo-close" data-id="${b.id}" style="margin-top:8px;">Close</button>
            </div>
        `).join('') || '<div class="muted">No BOLOs.</div>';

        container.querySelectorAll('.bolo-close').forEach((btn) => {
            btn.addEventListener('click', async () => {
                await request('update_bolo_status', { id: Number(btn.dataset.id), status: 'closed' });
                refresh();
            });
        });
    };

    document.getElementById('createBoloBtn').addEventListener('click', async () => {
        await request('create_bolo', {
            bolo_type: document.getElementById('boloType').value,
            title: document.getElementById('boloTitle').value,
            description: document.getElementById('boloDescription').value,
            target_identifier: document.getElementById('boloIdentifier').value,
            target_plate: document.getElementById('boloPlate').value
        });
        refresh();
    });

    document.getElementById('refreshBolos').addEventListener('click', refresh);
    refresh();
};

const renderEvidence = () => {
    pages.evidence.innerHTML = `
        <div class="card">
            <div class="result-title">Attach Evidence</div>
            <div class="row-3">
                <div class="field"><label>Report ID</label><input id="evidenceReportId" type="number" min="1" /></div>
                <div class="field"><label>Type</label><input id="evidenceType" placeholder="weapon, photo, dna" /></div>
                <div class="field"><label>Image URL</label><input id="evidenceUrl" placeholder="https://..." /></div>
            </div>
            <div class="field" style="margin-top:10px;"><label>Description</label><textarea id="evidenceDescription"></textarea></div>
            <button id="addEvidenceBtn" class="btn" style="margin-top:10px;">Add Evidence</button>
        </div>
        <div class="card">
            <div class="row">
                <div class="field"><label>Filter by Report ID (optional)</label><input id="evidenceFilterReport" type="number" min="1" /></div>
                <div class="field" style="justify-content:flex-end;"><button id="refreshEvidence" class="btn">Refresh Evidence</button></div>
            </div>
            <div id="evidenceResults" class="results" style="margin-top:10px;"></div>
        </div>
    `;

    const refresh = async () => {
        const reportIdValue = document.getElementById('evidenceFilterReport').value;
        const reportId = Number(reportIdValue || 0);
        const rows = await request('list_evidence', { report_id: reportId > 0 ? reportId : null });
        document.getElementById('evidenceResults').innerHTML = rows.map((e) => `
            <div class="result-item">
                <div class="result-title">#${e.id} Report #${e.report_id} (${escapeHtml(e.evidence_type)})</div>
                <div class="muted">${escapeHtml(e.description || '')}</div>
                <div class="muted">Image: ${escapeHtml(e.image_url || 'N/A')} | Added by: ${escapeHtml(e.added_by_name || 'N/A')}</div>
            </div>
        `).join('') || '<div class="muted">No evidence entries.</div>';
    };

    document.getElementById('addEvidenceBtn').addEventListener('click', async () => {
        await request('add_evidence', {
            report_id: Number(document.getElementById('evidenceReportId').value),
            evidence_type: document.getElementById('evidenceType').value,
            image_url: document.getElementById('evidenceUrl').value,
            description: document.getElementById('evidenceDescription').value,
            metadata: {}
        });
        refresh();
    });

    document.getElementById('refreshEvidence').addEventListener('click', refresh);
    refresh();
};

const renderRadar = () => {
    pages.radar.innerHTML = `
        <div class="card">
            <div class="row">
                <div class="field"><label>Plate Filter</label><input id="radarPlateFilter" placeholder="Optional plate" /></div>
                <div class="field" style="justify-content:flex-end;"><button id="refreshRadarLogs" class="btn">Refresh Radar Logs</button></div>
            </div>
            <div id="radarResults" class="results" style="margin-top:10px;"></div>
        </div>
    `;

    const refresh = async () => {
        const rows = await request('list_radar_logs', { plate: document.getElementById('radarPlateFilter').value.trim().toUpperCase() });
        document.getElementById('radarResults').innerHTML = rows.map((r) => `
            <div class="result-item">
                <div class="result-title">${escapeHtml(r.plate)} | ${Number(r.speed || 0)} mph</div>
                <div class="muted">${escapeHtml(r.location || 'Unknown location')} | Officer: ${escapeHtml(r.officer_name || 'N/A')} | ${escapeHtml(r.created_at || '')}</div>
            </div>
        `).join('') || '<div class="muted">No radar logs found.</div>';
    };

    document.getElementById('refreshRadarLogs').addEventListener('click', refresh);
    refresh();
};

const renderOfficer = async () => {
    const data = await request('get_officer_profile', {});
    const profile = data.profile || {};
    const reports = data.reports || [];
    const activities = profile.activity_log || [];

    pages.officer.innerHTML = `
        <div class="card">
            <div class="result-title">Officer Profile</div>
            <div class="muted">${escapeHtml(profile.full_name || 'N/A')} | Callsign: ${escapeHtml(profile.callsign || 'N/A')} | Rank: ${escapeHtml(profile.rank_label || 'N/A')}</div>
            <div class="field" style="margin-top:10px;">
                <label>Officer Notes</label>
                <textarea id="officerNotes">${escapeHtml(profile.notes || '')}</textarea>
            </div>
            <button id="saveOfficerNotes" class="btn" style="margin-top:8px;">Save Notes</button>
        </div>

        <div class="card">
            <div class="result-title">Officer Reports</div>
            <div class="results">
                ${reports.map((r) => `
                    <div class="result-item">
                        <div class="result-title">#${r.id} ${escapeHtml(r.title)}</div>
                        <div class="muted">${escapeHtml(r.report_type)} | ${escapeHtml(r.created_at)}</div>
                    </div>
                `).join('') || '<div class="muted">No reports authored yet.</div>'}
            </div>
        </div>

        <div class="card">
            <div class="result-title">Officer Activity Log</div>
            <div class="results">
                ${activities.slice().reverse().map((a) => `
                    <div class="result-item">
                        <div class="result-title">${escapeHtml(a.action || 'unknown')}</div>
                        <div class="muted">${escapeHtml(a.details || '')}</div>
                        <div class="muted">${escapeHtml(a.timestamp || '')}</div>
                    </div>
                `).join('') || '<div class="muted">No activity yet.</div>'}
            </div>
        </div>
    `;

    document.getElementById('saveOfficerNotes').addEventListener('click', async () => {
        await request('update_officer_notes', {
            notes: document.getElementById('officerNotes').value
        });
        notify('Officer notes updated.');
    });
};

const renderAllPages = async () => {
    renderDashboard();
    renderCitizens();
    renderVehicles();
    renderReports();
    renderWarrants();
    renderBolos();
    renderEvidence();
    renderRadar();
    await renderOfficer();
};

const closeMdt = async () => {
    await post('mdt:close', {});
};

const setupNavigation = () => {
    navButtons.forEach((btn) => {
        btn.addEventListener('click', () => setPage(btn.dataset.page));
    });
};

const setupWindowInteractions = () => {
    const header = document.getElementById('mdtHeader');
    const resize = document.getElementById('resizeHandle');

    let dragState = null;
    header.addEventListener('mousedown', (event) => {
        if (event.button !== 0) return;
        const rect = root.getBoundingClientRect();
        dragState = {
            offsetX: event.clientX - rect.left,
            offsetY: event.clientY - rect.top
        };
    });

    window.addEventListener('mousemove', (event) => {
        if (!dragState) return;
        const maxLeft = window.innerWidth - root.offsetWidth;
        const maxTop = window.innerHeight - root.offsetHeight;
        const nextLeft = Math.min(Math.max(0, event.clientX - dragState.offsetX), Math.max(0, maxLeft));
        const nextTop = Math.min(Math.max(0, event.clientY - dragState.offsetY), Math.max(0, maxTop));

        root.style.left = `${nextLeft}px`;
        root.style.top = `${nextTop}px`;
        root.style.transform = 'none';
    });

    window.addEventListener('mouseup', () => {
        dragState = null;
    });

    let resizeState = null;
    resize.addEventListener('mousedown', (event) => {
        if (event.button !== 0) return;
        event.stopPropagation();
        resizeState = {
            startX: event.clientX,
            startY: event.clientY,
            startW: root.offsetWidth,
            startH: root.offsetHeight
        };
    });

    window.addEventListener('mousemove', (event) => {
        if (!resizeState) return;

        const width = Math.min(window.innerWidth - 12, Math.max(820, resizeState.startW + (event.clientX - resizeState.startX)));
        const height = Math.min(window.innerHeight - 12, Math.max(540, resizeState.startH + (event.clientY - resizeState.startY)));

        root.style.width = `${width}px`;
        root.style.height = `${height}px`;
    });

    window.addEventListener('mouseup', () => {
        resizeState = null;
    });
};

closeBtn.addEventListener('click', closeMdt);

refreshBtn.addEventListener('click', async () => {
    const dashboard = await request('get_dashboard', {});
    state.dashboard = dashboard;
    renderDashboard();
});

window.addEventListener('message', async (event) => {
    const data = event.data;
    if (!data || !data.type) return;

    if (data.type === 'mdt:setOpen') {
        state.isOpen = !!data.payload.isOpen;
        root.classList.toggle('hidden', !state.isOpen);
        return;
    }

    if (data.type === 'mdt:init') {
        state.isOpen = true;
        root.classList.remove('hidden');
        state.dashboard = data.payload.dashboard || null;
        state.charges = await request('list_charges', {});
        await renderAllPages();
        setPage('dashboard');
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && state.isOpen) {
        closeMdt();
    }
});

setupNavigation();
setupWindowInteractions();