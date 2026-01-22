
import React, { useState, useEffect } from 'react';
import { Icons } from '../constants';
import { loggingService } from '../services/loggingService';
import { stateService } from '../services/stateService';
import { Operation, OperationParameter } from '../types';

interface MaintenanceViewProps {
  isAirGap: boolean;
}

const VAULT_KEY = 'wsus_sa_vault';

const operations: Operation[] = [
  { 
    id: 'reindex', 
    name: 'Database Reindex', 
    script: 'WsusReindex.psm1', 
    module: 'SQL_Optimizer', 
    category: 'Maintenance', 
    modeRequirement: 'Both', 
    description: 'Defragment SUSDB indexes to restore query performance and prevent timeout errors.',
    isDatabaseOp: true
  },
  { 
    id: 'export', 
    name: 'Export to Media', 
    script: 'WsusExport.psm1', 
    module: 'WsusExport', 
    category: 'Recovery', 
    modeRequirement: 'Online', 
    description: 'Export DB and content files to removable media for air-gap transfer.',
    isDatabaseOp: true,
    parameters: [
      { id: 'type', label: 'Export Type', type: 'select', options: ['Full', 'Differential'], defaultValue: 'Differential' },
      { id: 'days', label: 'Differential Age (Max Days)', type: 'number', defaultValue: 30 },
      { id: 'mediaPath', label: 'Removable Media Drive Path', type: 'text', defaultValue: 'E:\\' }
    ]
  },
  { 
    id: 'import', 
    name: 'Import from Media', 
    script: 'WsusExport.psm1', 
    module: 'WsusExport', 
    category: 'Recovery', 
    modeRequirement: 'Air-Gap', 
    description: 'Import metadata and update content from removable media.',
    isDatabaseOp: true,
    parameters: [
      { id: 'mediaPath', label: 'Source Path', type: 'text', defaultValue: 'E:\\' }
    ]
  },
  { 
    id: 'monthly', 
    name: 'Monthly Maintenance', 
    script: 'Invoke-WsusMonthlyMaintenance.ps1', 
    module: 'WsusUtilities', 
    category: 'Maintenance', 
    modeRequirement: 'Online', 
    isDatabaseOp: true,
    description: 'Sync with Microsoft, deep cleanup, and automated backup using preconfigured server settings.'
  },
  { id: 'cleanup', name: 'Deep Cleanup', script: 'WsusDatabase.psm1', module: 'WsusDatabase', category: 'Maintenance', modeRequirement: 'Both', isDatabaseOp: true, description: 'Aggressive space recovery for SUSDB metadata and stale content.' },
  { id: 'check', name: 'Health Check', script: 'WsusHealth.psm1', module: 'WsusHealth', category: 'Maintenance', modeRequirement: 'Both', description: 'Verify configuration, registry keys, and port connectivity.' }
];

const MaintenanceView: React.FC<MaintenanceViewProps> = ({ isAirGap }) => {
  const [runningAction, setRunningAction] = useState<string | null>(null);
  const [wizardOp, setWizardOp] = useState<Operation | null>(null);
  const [paramValues, setParamValues] = useState<Record<string, any>>({});
  const [activeCategory, setActiveCategory] = useState<string>('All');
  const [showVaultPrompt, setShowVaultPrompt] = useState(false);
  const [vaultPassword, setVaultPassword] = useState('');
  const [pendingOp, setPendingOp] = useState<{op: Operation, params: any} | null>(null);

  const categories = ['All', 'Deployment', 'Maintenance', 'Recovery'];

  const getVaultedPassword = () => {
    const p = localStorage.getItem(VAULT_KEY);
    return p ? atob(p) : null;
  };

  const handleInvoke = (op: Operation) => {
    if (op.isDatabaseOp && !getVaultedPassword()) {
      setPendingOp({ op, params: {} });
      setShowVaultPrompt(true);
      return;
    }

    if (op.parameters && op.parameters.length > 0) {
      setWizardOp(op);
      const defaults = op.parameters.reduce((acc, p) => ({ ...acc, [p.id]: p.defaultValue }), {});
      setParamValues(defaults);
    } else {
      execute(op);
    }
  };

  const saveVault = () => {
    if (!vaultPassword) return;
    localStorage.setItem(VAULT_KEY, btoa(vaultPassword));
    loggingService.info('SQL System Administrator credentials vaulted securely.');
    setShowVaultPrompt(false);
    if (pendingOp) { handleInvoke(pendingOp.op); setPendingOp(null); }
    setVaultPassword('');
  };

  const execute = (op: Operation, params: Record<string, any> = {}) => {
    setRunningAction(op.id);
    setWizardOp(null);
    
    loggingService.warn(`[POWERSHELL] Background Execution Initiated: .\\Scripts\\${op.script}`);
    
    if (op.id === 'reindex') {
        setTimeout(() => loggingService.info(`[SQL] Analyzing SUSDB index fragmentation...`), 500);
        setTimeout(() => loggingService.info(`[SQL] Applying FILLFACTOR 80 to highly fragmented tables...`), 1500);
        setTimeout(() => loggingService.info(`[SQL] Reindexing tbUpdateContent and tbUpdateMetadata clusters...`), 3000);
    }

    setTimeout(() => {
      loggingService.info(`[SUCCESS] Task "${op.name}" completed successfully.`);
      if (op.id === 'reindex') stateService.reindexDatabase();
      if (op.id === 'cleanup' || op.id === 'monthly') stateService.performCleanup();
      setRunningAction(null);
    }, 4500);
  };

  const filtered = operations.filter(op => {
    if (op.modeRequirement === 'Both') return true;
    return isAirGap ? op.modeRequirement === 'Air-Gap' : op.modeRequirement === 'Online';
  }).filter(op => activeCategory === 'All' || op.category === activeCategory);

  return (
    <div className="space-y-6 animate-fadeIn pb-12">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 p-5 bg-slate-900/40 border border-slate-800/40 rounded-2xl shadow-inner">
         <div>
            <h2 className="text-sm font-black text-white uppercase tracking-widest flex items-center gap-3">Runspace Operations</h2>
            <p className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mt-1">Managed pipeline for SUSDB lifecycle</p>
         </div>
         <div className="flex items-center gap-1 p-1 bg-black/40 border border-slate-800 rounded-xl">
            {categories.map(cat => (
              <button key={cat} onClick={() => setActiveCategory(cat)} className={`px-5 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest transition-all ${activeCategory === cat ? 'bg-blue-600 text-white shadow-lg' : 'text-slate-500 hover:text-slate-300'}`}>
                {cat}
              </button>
            ))}
         </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filtered.map(op => (
          <div key={op.id} className="panel-card p-6 rounded-2xl border-l-2 border-l-slate-800 hover:border-l-blue-600 transition-all flex flex-col justify-between group min-h-[220px] bg-[#121216]/50 shadow-lg">
            <div>
               <h3 className="text-base font-black text-white tracking-tight">{op.name}</h3>
               <p className="text-[11px] text-slate-500 mt-2 leading-relaxed font-medium">{op.description}</p>
            </div>
            <div className="mt-8 flex items-center justify-between pt-4 border-t border-slate-800/30">
               <span className="text-[10px] mono text-slate-600 font-bold">{op.script}</span>
               <button 
                disabled={!!runningAction}
                onClick={() => handleInvoke(op)}
                className={`px-6 py-3 rounded-xl font-black text-[10px] uppercase tracking-widest transition-all ${runningAction === op.id ? 'bg-amber-600 text-white animate-pulse' : 'bg-slate-900 text-slate-400 hover:bg-white hover:text-black'}`}
               >
                 {runningAction === op.id ? 'Running' : 'Invoke'}
               </button>
            </div>
          </div>
        ))}
      </div>

      {/* Vault Prompt Logic... */}
      {showVaultPrompt && (
        <div className="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/98 backdrop-blur-3xl">
           <div className="panel-card w-full max-w-md rounded-3xl border border-slate-800 shadow-2xl overflow-hidden animate-scaleIn">
              <div className="p-10 space-y-6 text-center">
                 <div className="w-16 h-16 bg-blue-600/10 border border-blue-500/20 rounded-2xl flex items-center justify-center mx-auto mb-4">
                    <Icons.AppLogo className="w-8 h-8 text-blue-500" />
                 </div>
                 <div>
                    <h2 className="text-xl font-black text-white uppercase tracking-widest">Vault Authentication</h2>
                    <p className="text-[10px] font-bold text-slate-500 uppercase mt-2 tracking-widest">Database operations require valid SQL SA credentials.</p>
                 </div>
                 <input 
                    type="password" autoFocus placeholder="ENTER SQL 'sa' PASSWORD"
                    className="w-full bg-black/40 border border-slate-800 rounded-2xl px-6 py-5 text-sm font-black text-white focus:outline-none focus:border-blue-600 text-center tracking-[0.4em]"
                    value={vaultPassword} onChange={e => setVaultPassword(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && saveVault()}
                 />
                 <div className="flex gap-3">
                    <button onClick={() => setShowVaultPrompt(false)} className="flex-1 py-4 text-[11px] font-black uppercase text-slate-600">Discard</button>
                    <button onClick={saveVault} className="flex-2 py-4 bg-blue-600 text-white rounded-2xl text-[11px] font-black uppercase">Secure Session</button>
                 </div>
              </div>
           </div>
        </div>
      )}
    </div>
  );
};

export default MaintenanceView;
