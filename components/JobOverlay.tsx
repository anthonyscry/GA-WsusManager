
import React from 'react';
import { BackgroundJob } from '../services/stateService';

interface JobOverlayProps {
  jobs: BackgroundJob[];
}

const JobOverlay: React.FC<JobOverlayProps> = ({ jobs }) => {
  if (jobs.length === 0) return null;

  return (
    <div className="fixed bottom-6 right-6 z-[200] space-y-3 w-80 animate-slideUp">
      {jobs.map(job => (
        <div key={job.id} className="bg-[#121216] border border-blue-500/30 rounded-2xl p-5 shadow-2xl backdrop-blur-xl">
           <div className="flex justify-between items-center mb-3">
              <span className="text-[10px] font-black text-white uppercase tracking-widest truncate max-w-[180px]">
                 {job.name}
              </span>
              <span className={`text-[9px] font-black uppercase ${job.status === 'Completed' ? 'text-emerald-500' : 'text-blue-500 animate-pulse'}`}>
                 {job.status === 'Completed' ? 'Success' : `${Math.round(job.progress)}%`}
              </span>
           </div>
           
           <div className="h-1.5 w-full bg-slate-900 rounded-full overflow-hidden">
              <div 
                className={`h-full transition-all duration-300 ${job.status === 'Completed' ? 'bg-emerald-500' : 'bg-blue-600'}`}
                style={{ width: `${job.progress}%` }}
              ></div>
           </div>
           
           <p className="text-[8px] font-bold text-slate-500 uppercase mt-2 tracking-tighter">
              {job.status === 'Running' ? 'Executing PowerShell Runspace...' : 'Finalizing Results...'}
           </p>
        </div>
      ))}
    </div>
  );
};

export default JobOverlay;
