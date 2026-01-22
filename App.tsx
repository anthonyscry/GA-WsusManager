
import React, { useState, useEffect } from 'react';
import { Icons } from './constants';
import Dashboard from './components/Dashboard';
import ComputersTable from './components/ComputersTable';
import LogsView from './components/LogsView';
import MaintenanceView from './components/MaintenanceView';
import AutomationView from './components/AutomationView';
import AuditView from './components/AuditView';
import AboutView from './components/AboutView';
import JobOverlay from './components/JobOverlay';
import { stateService } from './services/stateService';
import { loggingService } from './services/loggingService';

const App: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'dashboard' | 'computers' | 'maintenance' | 'automation' | 'logs' | 'audit' | 'help'>('dashboard');
  const [isAirGap, setIsAirGap] = useState(!navigator.onLine);
  const [refreshTimer, setRefreshTimer] = useState(30);
  const [stats, setStats] = useState(stateService.getStats());
  const [computers, setComputers] = useState(stateService.getComputers());
  const [jobs, setJobs] = useState(stateService.getJobs());
  const [showTerminal, setShowTerminal] = useState(false);

  useEffect(() => {
    loggingService.info('GA-WsusManager Command Center v3.8.6 Initialized');
    
    const unsubscribe = stateService.subscribe(() => {
      setStats({ ...stateService.getStats() });
      setComputers([...stateService.getComputers()]);
      setJobs([...stateService.getJobs()]);
    });

    const timer = setInterval(() => {
      setRefreshTimer(prev => {
        if (prev <= 1) {
          stateService.refreshTelemetry();
          return 30;
        }
        return prev - 1;
      });
    }, 1000);

    return () => { unsubscribe(); clearInterval(timer); };
  }, []);

  return (
    <div className="flex h-screen bg-[#0a0a0c] text-zinc-100 overflow-hidden font-sans select-none relative">
      <nav className="w-64 sidebar-navy border-r border-slate-800/40 flex flex-col z-50">
        <div className="p-8 pb-10 flex items-center gap-4">
          <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center text-white shadow-xl p-2">
             <Icons.AppLogo className="w-full h-full" />
          </div>
          <div className="leading-tight">
            <span className="text-sm font-black tracking-widest text-white block uppercase mono">WSUS_PRO</span>
            <span className="text-[9px] font-bold text-slate-500 uppercase tracking-tighter">Lab Console</span>
          </div>
        </div>

        <div className="flex-1 px-3 space-y-1 overflow-y-auto scrollbar-hide">
          <NavItem active={activeTab === 'dashboard'} onClick={() => setActiveTab('dashboard')} icon={<Icons.Dashboard className="w-4 h-4" />} label="Overview" />
          <NavItem active={activeTab === 'computers'} onClick={() => setActiveTab('computers')} icon={<Icons.Computers className="w-4 h-4" />} label="Inventory" />
          <NavItem active={activeTab === 'maintenance'} onClick={() => setActiveTab('maintenance')} icon={<Icons.Maintenance className="w-4 h-4" />} label="Operations" />
          <NavItem active={activeTab === 'automation'} onClick={() => setActiveTab('automation')} icon={<Icons.Automation className="w-4 h-4" />} label="Automation" />
          <NavItem active={activeTab === 'audit'} onClick={() => setActiveTab('audit')} icon={<Icons.Audit className="w-4 h-4" />} label="Auditing" />
          <div className="my-6 border-t border-slate-800/20 mx-4"></div>
          <NavItem active={activeTab === 'logs'} onClick={() => setActiveTab('logs')} icon={<Icons.Logs className="w-4 h-4" />} label="Full Logs" />
          <NavItem active={activeTab === 'help'} onClick={() => setActiveTab('help')} icon={<Icons.Help className="w-4 h-4" />} label="About" />
        </div>

        <button 
          onClick={() => setShowTerminal(!showTerminal)}
          className={`mx-4 mb-4 p-4 rounded-2xl border transition-all flex items-center justify-between ${showTerminal ? 'bg-blue-600/20 border-blue-500/40 text-blue-400' : 'bg-black/40 border-slate-800/40 text-slate-500 hover:border-slate-700'}`}
        >
          <div className="flex items-center gap-3">
            <div className={`w-1.5 h-1.5 rounded-full ${showTerminal ? 'bg-blue-400' : 'bg-slate-700'}`}></div>
            <span className="text-[10px] font-black uppercase tracking-widest">Live Terminal</span>
          </div>
          <Icons.Logs className="w-4 h-4" />
        </button>
      </nav>

      <main className="flex-1 flex flex-col overflow-hidden relative">
        <header className="h-16 bg-[#121216]/60 backdrop-blur-lg border-b border-slate-800/40 px-8 flex items-center justify-between z-40">
          <h1 className="text-xs font-black text-white uppercase tracking-[0.4em]">{activeTab}</h1>
          <div className="flex items-center gap-6">
             <div className="flex flex-col items-end">
                <span className="text-[8px] font-black text-slate-600 uppercase tracking-widest">Cycle</span>
                <span className="text-[11px] font-black text-blue-500 mono">{refreshTimer}s</span>
             </div>
          </div>
        </header>

        <div className="flex-1 overflow-y-auto p-10 bg-[#0a0a0c]">
          {activeTab === 'dashboard' && <Dashboard stats={stats} />}
          {activeTab === 'computers' && <ComputersTable computers={computers} />}
          {activeTab === 'maintenance' && <MaintenanceView isAirGap={isAirGap} />}
          {activeTab === 'automation' && <AutomationView />}
          {activeTab === 'audit' && <AuditView />}
          {activeTab === 'logs' && <LogsView />}
          {activeTab === 'help' && <AboutView />}
        </div>

        <div className={`absolute bottom-0 left-0 right-0 bg-black/95 backdrop-blur-2xl border-t border-blue-500/20 transition-all duration-300 z-[60] ${showTerminal ? 'h-64' : 'h-0'}`}>
          {showTerminal && <div className="h-full flex flex-col"><div className="px-6 py-2 border-b border-slate-800 flex justify-between items-center shrink-0"><span className="text-[9px] font-black text-blue-500 uppercase tracking-widest">Console Stream</span><button onClick={() => setShowTerminal(false)} className="text-slate-600 hover:text-white p-1">X</button></div><div className="flex-1 overflow-y-auto p-4"><LogsView hideHeader /></div></div>}
        </div>
      </main>

      <JobOverlay jobs={jobs} />
    </div>
  );
};

const NavItem = ({ active, onClick, icon, label }: any) => (
  <button onClick={onClick} className={`w-full flex items-center gap-4 px-5 py-3.5 rounded-xl text-[10px] font-bold uppercase tracking-widest transition-all ${active ? 'bg-blue-600 text-white shadow-xl' : 'text-slate-500 hover:text-slate-300 hover:bg-slate-900/40'}`}>
    {icon}{label}
  </button>
);

export default App;
