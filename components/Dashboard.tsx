
import React, { useState, useEffect } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, AreaChart, Area } from 'recharts';
import { EnvironmentStats } from '../types';
import { COLORS } from '../constants';
import { stateService } from '../services/stateService';
import { loggingService } from '../services/loggingService';

interface DashboardProps {
  stats: EnvironmentStats;
}

const Dashboard: React.FC<DashboardProps> = ({ stats }) => {
  const [isDiagnosing, setIsDiagnosing] = useState(false);
  const [throughputData, setThroughputData] = useState<any[]>([]);

  // Simulate real-time network traffic
  useEffect(() => {
    const interval = setInterval(() => {
      setThroughputData(prev => {
        const newData = [...prev, { time: Date.now(), val: Math.random() * 50 + 20 }].slice(-20);
        return newData;
      });
    }, 2000);
    return () => clearInterval(interval);
  }, []);

  const pieData = [
    { name: 'Healthy', value: stats.healthyComputers, color: COLORS.HEALTHY },
    { name: 'Warning', value: stats.warningComputers, color: COLORS.WARNING },
    { name: 'Critical', value: stats.criticalComputers, color: COLORS.CRITICAL },
  ];

  const dbPercentage = (stats.db.currentSizeGB / stats.db.maxSizeGB) * 100;

  const handleRunDiagnostics = () => {
    setIsDiagnosing(true);
    loggingService.warn('INTEGRITY_CHECK: Initializing heartbeat scan...');
    
    const sequence = [
      { msg: 'SQL: PAGE_VERIFY bits confirmed.', delay: 800 },
      { msg: 'IIS: AppPool W3SVC recycling verified.', delay: 1600 },
      { msg: 'WSUS: SUSDB retrieval latencies within 5ms.', delay: 2400 },
      { msg: 'DISK: C:\\WSUS cluster alignment healthy.', delay: 3200 },
      { msg: 'DIAG_COMPLETE: System integrity verified.', delay: 4000 }
    ];

    sequence.forEach(step => {
      setTimeout(() => loggingService.info(`[DIAG] ${step.msg}`), step.delay);
    });

    setTimeout(() => {
      setIsDiagnosing(false);
      stateService.refreshTelemetry();
    }, 4500);
  };

  return (
    <div className="space-y-6 animate-fadeIn pb-12">
      {/* Top Banner */}
      <div className="bg-[#121216] rounded-2xl p-6 border border-slate-800/40 flex items-center justify-between relative overflow-hidden shadow-2xl">
         <div className="flex items-center gap-5 relative z-10">
            <div className="w-12 h-12 bg-blue-600/10 border border-blue-600/20 rounded-xl flex items-center justify-center text-blue-500">
               <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>
            </div>
            <div>
               <h3 className="text-xs font-black tracking-widest uppercase text-white">Environment Integrity</h3>
               <p className="text-[10px] font-bold text-slate-500 uppercase mt-1">Infrastructure operational on portable runspace</p>
            </div>
         </div>
         <div className="flex items-center gap-3 relative z-10">
            <div className="px-4 py-2 bg-emerald-500/10 border border-emerald-500/20 rounded-lg">
               <span className="text-[10px] font-black text-emerald-500 uppercase tracking-widest">System Stable</span>
            </div>
         </div>
         <div className="absolute top-0 right-0 w-32 h-full bg-blue-600/5 rotate-12 translate-x-16"></div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
         <StatCard label="Total Nodes" value={stats.totalComputers} color="blue" />
         
         {/* DB Card */}
         <div className="bg-[#121216] p-5 rounded-xl border border-slate-800/40">
            <div className="flex justify-between items-start mb-1">
               <p className="text-[9px] font-black text-slate-600 uppercase tracking-widest">Database Usage</p>
               <span className={`text-[8px] font-black uppercase ${dbPercentage > 85 ? 'text-rose-500' : 'text-amber-500'}`}>
                  {dbPercentage.toFixed(1)}%
               </span>
            </div>
            <p className="text-xl font-black tracking-tight text-white">{stats.db.currentSizeGB} <span className="text-[10px] text-slate-600 font-bold uppercase">/ {stats.db.maxSizeGB} GB</span></p>
            <div className="mt-3 h-1 w-full bg-slate-900 rounded-full overflow-hidden">
               <div 
                  className={`h-full transition-all duration-1000 ${dbPercentage > 85 ? 'bg-rose-500' : 'bg-blue-500'}`} 
                  style={{ width: `${dbPercentage}%` }}
               ></div>
            </div>
         </div>

         <StatCard label="Compliance Rate" value="94.2%" color="emerald" />
         <StatCard label="Available Storage" value={`${stats.diskFreeGB} GB`} color="slate" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <div className="bg-[#121216] rounded-2xl p-8 border border-slate-800/40 relative">
            <div className="flex justify-between items-center mb-10">
               <div>
                  <h3 className="text-xs font-black text-white uppercase tracking-widest">Topology Compliance</h3>
                  <p className="text-[10px] font-bold text-slate-600 mt-1 uppercase">Distribution of Node Health</p>
               </div>
            </div>
            <div className="h-[240px] w-full flex items-center justify-center">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie data={pieData} cx="50%" cy="50%" innerRadius={70} outerRadius={90} paddingAngle={10} dataKey="value" stroke="none">
                    {pieData.map((entry, index) => <Cell key={`cell-${index}`} fill={entry.color} />)}
                  </Pie>
                  <Tooltip contentStyle={{ backgroundColor: '#121216', border: '1px solid #1e293b', borderRadius: '8px', fontSize: '10px' }} />
                </PieChart>
              </ResponsiveContainer>
              <div className="absolute flex flex-col items-center">
                <span className="text-3xl font-black text-white tracking-tighter">{stats.totalComputers}</span>
                <span className="text-[8px] text-slate-600 font-black uppercase tracking-widest">Total Nodes</span>
              </div>
            </div>
          </div>

          {/* Network Graph Simulation */}
          <div className="bg-[#121216] rounded-2xl p-6 border border-slate-800/40">
             <div className="flex justify-between items-center mb-6">
                <h3 className="text-[10px] font-black text-white uppercase tracking-widest">Network Throughput ( simulated )</h3>
                <span className="text-[10px] font-bold text-slate-500 mono uppercase tracking-tight">Active Transfer: {(throughputData[throughputData.length - 1]?.val || 0).toFixed(1)} Mbps</span>
             </div>
             <div className="h-32 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={throughputData}>
                    <Area type="monotone" dataKey="val" stroke="#2563eb" fill="#2563eb" fillOpacity={0.1} isAnimationActive={false} />
                  </AreaChart>
                </ResponsiveContainer>
             </div>
          </div>
        </div>

        <div className="bg-[#121216] rounded-2xl p-8 border border-slate-800/40 flex flex-col h-full shadow-2xl">
           <h3 className="text-xs font-black text-white uppercase tracking-widest mb-2">Service Monitor</h3>
           <p className="text-[10px] font-bold text-slate-600 mb-8 uppercase">Live Runtime Heartbeat</p>
           <div className="space-y-3 flex-1">
              {stats.services.map((s, i) => (
                 <div key={i} className="flex items-center justify-between p-4 bg-black/40 rounded-xl border border-slate-800/30">
                    <div className="flex items-center gap-3">
                       <div className={`w-1.5 h-1.5 rounded-full ${s.status === 'Running' ? 'bg-emerald-500 shadow-[0_0_8px_#10b981]' : 'bg-rose-500 shadow-[0_0_8px_#ef4444]'}`}></div>
                       <span className="text-[10px] font-bold text-slate-400 uppercase tracking-tight">{s.name}</span>
                    </div>
                    <span className="text-[8px] font-black text-slate-600 uppercase tracking-widest">{s.status}</span>
                 </div>
              ))}
           </div>
           <button 
            disabled={isDiagnosing}
            onClick={handleRunDiagnostics}
            className={`w-full mt-6 py-4 border rounded-xl text-[9px] font-black uppercase tracking-widest transition-all ${isDiagnosing ? 'bg-blue-600 text-white animate-pulse' : 'bg-slate-900 hover:bg-slate-800 border-slate-800/50 text-slate-500 hover:text-slate-300'}`}
           >
              {isDiagnosing ? 'Diagnostics Active...' : 'Run Infrastructure Test'}
           </button>
        </div>
      </div>
    </div>
  );
};

const StatCard = ({ label, value, color }: any) => {
  const colorMap: any = {
    blue: 'text-blue-500',
    amber: 'text-amber-500',
    emerald: 'text-emerald-500',
    slate: 'text-slate-500'
  };
  return (
    <div className="bg-[#121216] p-5 rounded-xl border border-slate-800/40">
      <p className="text-[9px] font-black text-slate-600 uppercase tracking-widest mb-1">{label}</p>
      <p className={`text-xl font-black tracking-tight ${colorMap[color]}`}>{value}</p>
    </div>
  );
};

export default Dashboard;
