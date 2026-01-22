
import React from 'react';
import { Icons } from '../constants';

const AboutView: React.FC = () => {
  return (
    <div className="space-y-8 animate-fadeIn max-w-5xl mx-auto py-12">
      {/* App Mission & Context */}
      <div className="panel-card p-10 rounded-3xl bg-[#121216] border border-slate-800/60 shadow-2xl relative overflow-hidden">
         <div className="absolute top-0 right-0 w-96 h-96 bg-blue-600/5 rounded-full -translate-y-1/2 translate-x-1/2 blur-3xl"></div>
         
         <div className="relative z-10 flex flex-col md:flex-row gap-10 items-start">
            <div className="w-16 h-16 bg-blue-600 rounded-2xl flex items-center justify-center shadow-2xl border border-blue-400/20 shrink-0">
               <Icons.AppLogo className="w-8 h-8 text-white" />
            </div>
            
            <div className="space-y-6">
               <div>
                  <h2 className="text-[10px] font-black text-blue-500 uppercase tracking-[0.4em] mb-2">Management Suite</h2>
                  <h1 className="text-3xl font-black text-white uppercase tracking-tight">WSUS_PRO Engine</h1>
                  <p className="text-sm font-medium text-slate-400 leading-relaxed mt-4 max-w-3xl">
                     A specialized administrative interface designed for high-security environments and classified enclaves. 
                     This utility bridges the gap between traditional WSUS management and the rigorous uptime requirements of air-gapped enclaves, 
                     providing a unified control plane for SQL Express and the W3SVC update pipeline.
                  </p>
               </div>

               <div className="grid grid-cols-1 md:grid-cols-3 gap-6 pt-6 border-t border-slate-800/50">
                  <div className="space-y-2">
                     <span className="text-[9px] font-black text-slate-500 uppercase tracking-widest block">Primary Objective</span>
                     <p className="text-[11px] font-bold text-slate-300">Automate high-frequency maintenance to prevent SUSDB bloat.</p>
                  </div>
                  <div className="space-y-2">
                     <span className="text-[9px] font-black text-slate-500 uppercase tracking-widest block">Compliance Focus</span>
                     <p className="text-[11px] font-bold text-slate-300">Real-time telemetry and auditing for STIG/RMF consistency.</p>
                  </div>
                  <div className="space-y-2">
                     <span className="text-[9px] font-black text-slate-500 uppercase tracking-widest block">Architecture</span>
                     <p className="text-[11px] font-bold text-slate-300">Optimized for SQL Express 2022 and Windows Server enclaves.</p>
                  </div>
               </div>
            </div>
         </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
         {/* Core Functions */}
         <div className="panel-card p-8 rounded-2xl border border-slate-800/40 bg-[#121216]/50">
            <h3 className="text-[10px] font-black text-white uppercase tracking-[0.3em] mb-6 flex items-center gap-2">
               <div className="w-1.5 h-1.5 bg-blue-600 rounded-full"></div>
               Operational Capabilities
            </h3>
            <div className="space-y-4 text-slate-400 text-xs leading-relaxed font-medium">
               <ul className="space-y-4">
                  <li className="flex gap-4 p-4 bg-black/30 rounded-xl border border-slate-800/20">
                     <span className="text-blue-500 font-black text-sm">01</span>
                     <div>
                        <span className="text-white font-bold block mb-1">Metadata Optimization</span>
                        <span>Recursive cleanup of expired updates and unneeded revisions within the SUSDB database.</span>
                     </div>
                  </li>
                  <li className="flex gap-4 p-4 bg-black/30 rounded-xl border border-slate-800/20">
                     <span className="text-blue-500 font-black text-sm">02</span>
                     <div>
                        <span className="text-white font-bold block mb-1">Air-Gap Synchronization</span>
                        <span>Protocol-safe export and import tools for moving update metadata across physical security barriers.</span>
                     </div>
                  </li>
                  <li className="flex gap-4 p-4 bg-black/30 rounded-xl border border-slate-800/20">
                     <span className="text-blue-500 font-black text-sm">03</span>
                     <div>
                        <span className="text-white font-bold block mb-1">Service Orchestration</span>
                        <span>Managed recovery and status monitoring for SQL, IIS, and WSUS core services.</span>
                     </div>
                  </li>
               </ul>
            </div>
         </div>

         <div className="space-y-8">
            {/* Technical Specs */}
            <div className="panel-card p-8 rounded-2xl border border-slate-800/40 bg-[#121216]/50">
               <h3 className="text-[10px] font-black text-white uppercase tracking-[0.3em] mb-6 flex items-center gap-2">
                  <div className="w-1.5 h-1.5 bg-blue-600 rounded-full"></div>
                  Build Specifications
               </h3>
               <div className="space-y-3">
                  <div className="p-4 bg-black/40 rounded-xl border border-slate-800/30 flex justify-between items-center">
                     <span className="text-[9px] font-black text-slate-500 uppercase tracking-widest">Version Status</span>
                     <span className="text-[10px] mono font-bold text-white">3.8.6 Stable</span>
                  </div>
                  <div className="p-4 bg-black/40 rounded-xl border border-slate-800/30 flex justify-between items-center">
                     <span className="text-[9px] font-black text-slate-500 uppercase tracking-widest">Core Engine</span>
                     <span className="text-[10px] mono font-bold text-white">PRO_INTEGRATOR_V5</span>
                  </div>
                  <div className="p-4 bg-black/40 rounded-xl border border-slate-800/30 flex justify-between items-center">
                     <span className="text-[9px] font-black text-slate-500 uppercase tracking-widest">Target Platform</span>
                     <span className="text-[10px] mono font-bold text-blue-500">GA-ASI Systems</span>
                  </div>
               </div>
            </div>

            {/* Simplified Creator Section */}
            <div className="panel-card p-8 rounded-2xl border border-slate-800/40 bg-[#121216]/50 flex items-center gap-6">
               <div className="w-12 h-12 bg-slate-900 border border-slate-800 rounded-xl flex items-center justify-center shrink-0">
                  <div className="w-6 h-6 bg-blue-600/20 rounded-md border border-blue-500/30 flex items-center justify-center">
                     <div className="w-2 h-2 bg-blue-500 rounded-full shadow-[0_0_8px_#3b82f6]"></div>
                  </div>
               </div>
               <div className="min-w-0">
                  <p className="text-[9px] font-black text-slate-500 uppercase tracking-widest mb-1">Developer</p>
                  <h4 className="text-lg font-black text-white tracking-tight truncate">Tony Tran</h4>
                  <p className="text-[10px] font-bold text-slate-500 uppercase tracking-tight mt-0.5">Created by Tony Tran</p>
                  <a href="mailto:tony.tran@ga-asi.com" className="text-[10px] font-bold text-blue-500/80 hover:text-blue-400 transition-colors mt-2 block tracking-tight">tony.tran@ga-asi.com</a>
               </div>
            </div>
         </div>
      </div>
    </div>
  );
};

export default AboutView;
