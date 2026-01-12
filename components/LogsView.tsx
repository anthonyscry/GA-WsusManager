
import React, { useEffect, useState, useRef } from 'react';
import { LogEntry, LogLevel } from '../types';
import { loggingService } from '../services/loggingService';

interface LogsViewProps {
  hideHeader?: boolean;
}

const LogsView: React.FC<LogsViewProps> = ({ hideHeader = false }) => {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [filter, setFilter] = useState<LogLevel | 'ALL'>('ALL');
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const refreshLogs = () => {
      setLogs(loggingService.getLogs().reverse());
    };
    refreshLogs();

    window.addEventListener('wsus_log_added', refreshLogs);
    window.addEventListener('wsus_log_cleared', refreshLogs);
    return () => {
      window.removeEventListener('wsus_log_added', refreshLogs);
      window.removeEventListener('wsus_log_cleared', refreshLogs);
    };
  }, []);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs]);

  const filteredLogs = filter === 'ALL' ? logs : logs.filter(l => l.level === filter);

  const getLevelColor = (level: LogLevel) => {
    switch (level) {
      case LogLevel.ERROR: return "text-rose-500";
      case LogLevel.WARNING: return "text-amber-500";
      default: return "text-blue-400";
    }
  };

  return (
    <div className={`flex flex-col h-full animate-fadeIn ${!hideHeader ? 'pb-8' : ''}`}>
      {!hideHeader && (
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-sm font-black text-white uppercase tracking-[0.2em]">System Console</h2>
            <p className="text-[10px] font-bold text-slate-500 uppercase mt-1 tracking-widest underline decoration-blue-500/30">WsusManager_v3.8.6.log</p>
          </div>
          
          <div className="flex items-center gap-3">
            <div className="flex p-1 bg-slate-900/50 rounded-lg border border-slate-800/50">
               {(['ALL', LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR] as const).map(f => (
                 <button 
                  key={f}
                  onClick={() => setFilter(f)}
                  className={`px-3 py-1.5 rounded text-[9px] font-black uppercase tracking-widest transition-all ${filter === f ? 'bg-blue-600 text-white shadow-lg' : 'text-slate-500 hover:text-slate-300'}`}
                 >
                   {f}
                 </button>
               ))}
            </div>
            <button onClick={() => loggingService.clearLogs()} className="px-4 py-2.5 text-[9px] font-black uppercase tracking-widest text-rose-500/60 hover:text-rose-500 border border-rose-500/20 hover:border-rose-500/50 rounded-lg transition-all">
              Clear Buffer
            </button>
          </div>
        </div>
      )}

      <div className={`flex-1 overflow-hidden flex flex-col ${!hideHeader ? 'panel-card rounded-2xl bg-black/60 border border-slate-800/60 shadow-2xl' : ''}`}>
        <div ref={scrollRef} className="flex-1 p-6 font-mono text-[11px] overflow-y-auto scrollbar-hide space-y-1.5">
          {filteredLogs.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center gap-4">
               <p className="text-slate-600 font-bold uppercase tracking-widest text-[10px]">Buffer empty.</p>
            </div>
          ) : (
            filteredLogs.map((log) => (
              <div key={log.id} className="flex gap-4 group hover:bg-slate-800/20 py-0.5 px-2 rounded -mx-2 transition-colors">
                <span className="text-slate-700 whitespace-nowrap hidden md:block">[{log.timestamp.split('T')[1].split('.')[0]}]</span>
                <span className={`font-black uppercase tracking-tighter w-12 flex-shrink-0 ${getLevelColor(log.level)}`}>{log.level}</span>
                <span className="text-blue-500 font-bold flex-shrink-0 opacity-50">C:\&gt;</span>
                <span className="text-slate-300 font-medium leading-relaxed">{log.message}</span>
              </div>
            ))
          )}
        </div>
        
        <div className="h-10 bg-slate-900/40 border-t border-slate-800/50 px-6 flex items-center justify-between shrink-0">
           <div className="flex items-center gap-6">
              <span className="flex items-center gap-2">
                 <div className="w-1 h-1 rounded-full bg-emerald-500 animate-pulse"></div>
                 <span className="text-[8px] font-black text-emerald-500/70 uppercase tracking-widest">Buffer Listening</span>
              </span>
           </div>
           <span className="text-[9px] font-bold text-slate-700 uppercase tracking-widest">Active Entries: {filteredLogs.length}</span>
        </div>
      </div>
    </div>
  );
};

export default LogsView;
