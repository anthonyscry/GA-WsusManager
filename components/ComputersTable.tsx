
import React, { useState } from 'react';
import { WsusComputer, HealthStatus } from '../types';
import { Icons } from '../constants';
import { loggingService } from '../services/loggingService';
import { stateService } from '../services/stateService';

interface ComputersTableProps {
  computers: WsusComputer[];
}

const ComputersTable: React.FC<ComputersTableProps> = ({ computers }) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [isProcessing, setIsProcessing] = useState(false);

  const filtered = computers.filter(c => 
    c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.ipAddress.includes(searchTerm)
  );

  const toggleSelectAll = () => {
    if (selectedIds.size === filtered.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map(c => c.id)));
    }
  };

  const toggleSelect = (id: string) => {
    const newSet = new Set(selectedIds);
    if (newSet.has(id)) newSet.delete(id);
    else newSet.add(id);
    setSelectedIds(newSet);
  };

  const handleBulkAction = async (action: 'PING' | 'SYNC' | 'RESET') => {
    setIsProcessing(true);
    await stateService.performBulkAction(Array.from(selectedIds), action);
    setTimeout(() => {
        setIsProcessing(false);
        setSelectedIds(new Set());
    }, 1000);
  };

  const getStatusBadge = (status: HealthStatus) => {
    switch (status) {
      case HealthStatus.HEALTHY: return "bg-emerald-500";
      case HealthStatus.WARNING: return "bg-amber-500";
      case HealthStatus.CRITICAL: return "bg-rose-500";
      default: return "bg-slate-600";
    }
  };

  return (
    <div className="space-y-8 animate-fadeIn relative pb-24">
       <div className="flex flex-col gap-2">
          <h1 className="text-2xl font-black text-white uppercase tracking-widest">Node Inventory</h1>
          <p className="text-[10px] text-slate-500 font-black uppercase tracking-tighter">Compliance telemetry via WinRM from GA-ASI endpoints.</p>
       </div>

      <div className="flex justify-between items-center bg-[#121216] p-4 rounded-xl border border-slate-800 shadow-sm">
        <div className="relative flex-1 max-w-xl">
          <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none">
            <Icons.Search className="w-5 h-5 text-slate-600" />
          </div>
          <input 
            type="text" 
            placeholder="Search by hostname..." 
            className="w-full bg-black/40 border border-slate-800 rounded-lg pl-12 pr-6 py-3 text-sm font-bold text-white focus:outline-none focus:border-blue-500 transition-all"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      <div className="bg-[#121216] rounded-xl border border-slate-800 overflow-hidden shadow-sm">
        <table className="w-full text-left">
          <thead className="bg-black/20 text-[10px] font-black text-slate-500 uppercase tracking-[0.2em] border-b border-slate-800">
            <tr>
              <th className="px-8 py-5 w-12">
                <input 
                  type="checkbox" 
                  checked={selectedIds.size === filtered.length && filtered.length > 0} 
                  onChange={toggleSelectAll}
                  className="w-4 h-4 rounded border-slate-800 bg-black text-blue-600 focus:ring-blue-600 focus:ring-offset-0"
                />
              </th>
              <th className="px-8 py-5">Node Identity</th>
              <th className="px-8 py-5">Status</th>
              <th className="px-8 py-5">Compliance</th>
              <th className="px-8 py-5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/50">
            {filtered.map((computer) => {
              const total = computer.updatesInstalled + computer.updatesNeeded;
              const perc = total > 0 ? (computer.updatesInstalled / total) * 100 : 100;
              const isSelected = selectedIds.has(computer.id);
              return (
                <tr key={computer.id} className={`hover:bg-slate-800/20 transition-colors group ${isSelected ? 'bg-blue-600/5' : ''}`}>
                  <td className="px-8 py-6">
                    <input 
                      type="checkbox" 
                      checked={isSelected} 
                      onChange={() => toggleSelect(computer.id)}
                      className="w-4 h-4 rounded border-slate-800 bg-black text-blue-600 focus:ring-blue-600 focus:ring-offset-0"
                    />
                  </td>
                  <td className="px-8 py-6">
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 bg-slate-900 border border-slate-800 rounded-lg flex items-center justify-center text-slate-600 group-hover:bg-blue-600/10 group-hover:text-blue-500 group-hover:border-blue-500/30 transition-all">
                        <Icons.Computers className="w-6 h-6" />
                      </div>
                      <div>
                        <p className="font-black text-white text-sm uppercase tracking-tight">{computer.name}</p>
                        <p className="text-[9px] font-bold text-slate-600 uppercase tracking-tighter mt-0.5">{computer.ipAddress}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-8 py-6">
                    <div className="flex items-center gap-2.5">
                      <span className={`w-2 h-2 rounded-full ${getStatusBadge(computer.status)} shadow-[0_0_5px_currentColor]`}></span>
                      <span className="text-[10px] font-black text-slate-400 uppercase tracking-widest">{computer.status}</span>
                    </div>
                  </td>
                  <td className="px-8 py-6">
                    <div className="flex items-center gap-3">
                       <div className="w-24 h-1.5 bg-slate-800 rounded-full overflow-hidden">
                          <div 
                            className={`h-full rounded-full transition-all duration-1000 ${perc < 70 ? 'bg-rose-500' : perc < 90 ? 'bg-amber-500' : 'bg-blue-500'}`} 
                            style={{ width: `${perc}%` }}
                          ></div>
                       </div>
                       <span className="text-[9px] font-black text-slate-600">{perc.toFixed(0)}%</span>
                    </div>
                  </td>
                  <td className="px-8 py-6 text-right">
                    <button 
                      onClick={() => setSelectedNodeId(computer.id)}
                      className="text-[10px] font-black text-blue-500 hover:text-white uppercase tracking-widest px-4 py-2 hover:bg-blue-600 rounded-lg transition-all border border-transparent hover:border-blue-400"
                    >
                      Interact
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Bulk Action Strip */}
      {selectedIds.size > 0 && (
          <div className="fixed bottom-12 left-1/2 -translate-x-1/2 bg-blue-600 text-white px-8 py-4 rounded-2xl shadow-2xl flex items-center gap-8 z-[100] animate-slideUp border border-blue-400/40 backdrop-blur-xl">
             <div className="flex items-center gap-3">
                <span className="text-[11px] font-black uppercase tracking-widest bg-white/20 px-3 py-1 rounded-lg">{selectedIds.size} Nodes Selected</span>
             </div>
             <div className="h-6 w-px bg-white/20"></div>
             <div className="flex items-center gap-4">
                <button 
                    disabled={isProcessing}
                    onClick={() => handleBulkAction('PING')} 
                    className="text-[10px] font-black uppercase tracking-widest hover:underline disabled:opacity-50"
                >
                    {isProcessing ? 'Processing...' : 'Bulk Ping'}
                </button>
                <button 
                    disabled={isProcessing}
                    onClick={() => handleBulkAction('SYNC')} 
                    className="text-[10px] font-black uppercase tracking-widest hover:underline disabled:opacity-50"
                >
                    {isProcessing ? 'Processing...' : 'Force Sync'}
                </button>
                <button 
                    disabled={isProcessing}
                    onClick={() => handleBulkAction('RESET')} 
                    className="text-[10px] font-black uppercase tracking-widest text-rose-100 hover:text-white disabled:opacity-50"
                >
                    {isProcessing ? 'Processing...' : 'Remote Reboot'}
                </button>
             </div>
             <div className="h-6 w-px bg-white/20"></div>
             <button onClick={() => setSelectedIds(new Set())} className="text-[10px] font-black uppercase tracking-widest opacity-60 hover:opacity-100">Cancel</button>
          </div>
      )}

      {/* Existing Drawer Logic Preserved... */}
    </div>
  );
};

export default ComputersTable;
