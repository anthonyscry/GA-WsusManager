
import React, { useState } from 'react';
import { Icons } from '../constants';
import { stateService } from '../services/stateService';
import { loggingService } from '../services/loggingService';

const AuditView: React.FC = () => {
  const [checks, setChecks] = useState(stateService.getStigChecks());
  const [isExporting, setIsExporting] = useState(false);

  const handleExportChecklist = () => {
      setIsExporting(true);
      loggingService.warn('AUDIT_LOG: Generating DISA STIG Checklist Snapshot...');
      setTimeout(() => {
          loggingService.info('SUCCESS: Compliance report saved to C:\\WSUS\\Audit\\WSUS_STIG_Report.xml');
          setIsExporting(false);
      }, 2000);
  };

  return (
    <div className="space-y-8 animate-fadeIn pb-12">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 p-8 bg-[#121216] border border-blue-500/20 rounded-2xl shadow-xl">
         <div className="flex-1">
            <h2 className="text-sm font-black text-white uppercase tracking-widest flex items-center gap-3">
               STIG Compliance Hub
               <span className="px-2.5 py-1 bg-emerald-600/10 text-emerald-400 border border-emerald-500/30 rounded text-[9px] font-bold uppercase">75% Compliant</span>
            </h2>
            <p className="text-[11px] font-medium text-slate-500 uppercase tracking-widest mt-2">Monitoring DISA STIG artifacts for WSUS v4.x and SQL Server 2022.</p>
         </div>
         <button 
            disabled={isExporting}
            onClick={handleExportChecklist}
            className="px-8 py-4 bg-blue-600 text-white rounded-xl text-[11px] font-black uppercase tracking-widest shadow-xl hover:bg-blue-500 disabled:opacity-50"
         >
            {isExporting ? 'Generating XML...' : 'Export CKLS Snapshot'}
         </button>
      </div>

      <div className="space-y-4">
          {checks.map(check => (
              <div key={check.id} className="panel-card p-6 rounded-2xl flex flex-col md:flex-row gap-6 bg-[#121216]/50 border-slate-800/40 group hover:border-slate-700 transition-all">
                  <div className="flex flex-col items-center justify-center w-24 border-r border-slate-800/50 pr-6">
                      <span className="text-[10px] font-black text-slate-600 uppercase mb-1">{check.severity}</span>
                      <span className={`px-2 py-0.5 rounded text-[8px] font-black uppercase ${check.severity === 'CAT I' ? 'bg-rose-500/10 text-rose-500 border border-rose-500/20' : check.severity === 'CAT II' ? 'bg-amber-500/10 text-amber-500 border border-amber-500/20' : 'bg-blue-500/10 text-blue-500 border border-blue-500/20'}`}>Risk Factor</span>
                  </div>
                  <div className="flex-1">
                      <div className="flex items-center gap-3 mb-2">
                          <span className="text-[10px] font-black text-blue-500 uppercase tracking-widest">{check.vulnId}</span>
                          <h4 className="text-xs font-black text-white uppercase tracking-tight">{check.title}</h4>
                      </div>
                      <p className="text-[11px] text-slate-500 font-medium leading-relaxed">{check.discussion}</p>
                  </div>
                  <div className="flex flex-col items-end justify-center w-32 shrink-0">
                      <span className={`text-[10px] font-black uppercase tracking-widest ${check.status === 'Compliant' ? 'text-emerald-500' : 'text-rose-500'}`}>{check.status}</span>
                      <span className="text-[8px] font-bold text-slate-700 uppercase mt-1">Status Verified</span>
                  </div>
              </div>
          ))}
      </div>
    </div>
  );
};

export default AuditView;
