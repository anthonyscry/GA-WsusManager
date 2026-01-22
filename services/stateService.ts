
import { EnvironmentStats, WsusComputer, HealthStatus, ScheduledTask, StigCheck } from '../types';
import { mockStats, mockComputers } from './mockData';
import { loggingService } from './loggingService';

const STORAGE_KEY_STATS = 'wsus_pro_stats';
const STORAGE_KEY_COMPUTERS = 'wsus_pro_computers';
const STORAGE_KEY_TASKS = 'wsus_pro_tasks';

export interface BackgroundJob {
  id: string;
  name: string;
  progress: number;
  status: 'Running' | 'Completed' | 'Failed';
  startTime: number;
}

class StateService {
  private stats: EnvironmentStats;
  private computers: WsusComputer[];
  private tasks: ScheduledTask[];
  private jobs: BackgroundJob[] = [];
  private listeners: Set<() => void> = new Set();

  constructor() {
    const savedStats = localStorage.getItem(STORAGE_KEY_STATS);
    const savedComputers = localStorage.getItem(STORAGE_KEY_COMPUTERS);
    const savedTasks = localStorage.getItem(STORAGE_KEY_TASKS);

    this.stats = savedStats ? JSON.parse(savedStats) : { ...mockStats };
    this.computers = savedComputers ? JSON.parse(savedComputers) : [...mockComputers];
    this.tasks = savedTasks ? JSON.parse(savedTasks) : [
      {
        id: '1',
        name: 'Monthly_WSUS_Cleanup',
        trigger: 'Monthly',
        time: '02:00',
        status: 'Ready',
        lastRun: '2023-10-01 02:00',
        nextRun: '2023-11-01 02:00'
      }
    ];
  }

  private notify() {
    this.listeners.forEach(l => l());
    localStorage.setItem(STORAGE_KEY_STATS, JSON.stringify(this.stats));
    localStorage.setItem(STORAGE_KEY_COMPUTERS, JSON.stringify(this.computers));
    localStorage.setItem(STORAGE_KEY_TASKS, JSON.stringify(this.tasks));
  }

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  getStats() { return this.stats; }
  getComputers() { return this.computers; }
  getTasks() { return this.tasks; }
  getJobs() { return this.jobs; }

  startJob(name: string, durationMs: number = 3000, onComplete?: () => void) {
    const jobId = Math.random().toString(36).substr(2, 9);
    const newJob: BackgroundJob = {
      id: jobId,
      name,
      progress: 0,
      status: 'Running',
      startTime: Date.now()
    };
    
    this.jobs.push(newJob);
    this.notify();

    const interval = 100;
    const steps = durationMs / interval;
    let currentStep = 0;

    const timer = setInterval(() => {
      currentStep++;
      const jobIndex = this.jobs.findIndex(j => j.id === jobId);
      if (jobIndex !== -1) {
        this.jobs[jobIndex].progress = (currentStep / steps) * 100;
        
        if (currentStep >= steps) {
          this.jobs[jobIndex].status = 'Completed';
          this.jobs[jobIndex].progress = 100;
          clearInterval(timer);
          setTimeout(() => {
            this.jobs = this.jobs.filter(j => j.id !== jobId);
            this.notify();
          }, 2000);
          if (onComplete) onComplete();
        }
        this.notify();
      } else {
        clearInterval(timer);
      }
    }, interval);

    return jobId;
  }

  addTask(task: Omit<ScheduledTask, 'id' | 'status' | 'lastRun' | 'nextRun'>) {
    const newTask: ScheduledTask = {
      ...task,
      id: Math.random().toString(36).substr(2, 9),
      status: 'Ready',
      lastRun: 'Never',
      nextRun: 'Next Cycle'
    };
    this.tasks.push(newTask);
    this.notify();
    return newTask;
  }

  refreshTelemetry() {
    loggingService.info('Polling infrastructure for fresh telemetry...');
    this.stats.diskFreeGB = Math.max(10, +(this.stats.diskFreeGB + (Math.random() - 0.5) * 2).toFixed(2));
    this.stats.db.currentSizeGB = Math.min(10, +(this.stats.db.currentSizeGB + 0.005).toFixed(3));
    this.notify();
  }

  performCleanup() {
    this.startJob('Deep Cleanup Engine', 4000, () => {
        const reduction = 0.5 + Math.random();
        const oldSize = this.stats.db.currentSizeGB;
        this.stats.db.currentSizeGB = Math.max(1.2, +(oldSize - reduction).toFixed(2));
        this.stats.db.lastBackup = new Date().toISOString().replace('T', ' ').slice(0, 16);
        loggingService.warn(`SUSDB Optimization: Reclaimed ${(oldSize - this.stats.db.currentSizeGB).toFixed(2)} GB.`);
        this.notify();
    });
  }

  reindexDatabase() {
    this.startJob('SQL Index Defragmentation', 5000, () => {
        loggingService.info('SQL_SUCCESS: Fragmentation reduced from 34.2% to 0.4%.');
        this.notify();
    });
  }

  async performBulkAction(ids: string[], action: 'PING' | 'SYNC' | 'RESET') {
    this.startJob(`Bulk ${action} (${ids.length} Nodes)`, 3500, () => {
        for (const id of ids) {
            const computer = this.computers.find(c => c.id === id);
            if (!computer) continue;
            if (action === 'SYNC') {
                computer.lastSync = new Date().toISOString().replace('T', ' ').slice(0, 16);
                computer.updatesNeeded = 0;
                computer.status = HealthStatus.HEALTHY;
            } else if (action === 'RESET') {
                this.simulateReset(id);
            }
        }
        this.recalculateStats();
        this.notify();
    });
  }

  private recalculateStats() {
    this.stats.totalComputers = this.computers.length;
    this.stats.healthyComputers = this.computers.filter(c => c.status === HealthStatus.HEALTHY).length;
    this.stats.warningComputers = this.computers.filter(c => c.status === HealthStatus.WARNING).length;
    this.stats.criticalComputers = this.computers.filter(c => c.status === HealthStatus.CRITICAL).length;
  }

  async simulateReset(computerId: string) {
    const computer = this.computers.find(c => c.id === computerId);
    if (!computer) return;
    computer.status = HealthStatus.CRITICAL;
    this.notify();
    setTimeout(() => {
      computer.status = HealthStatus.HEALTHY;
      loggingService.info(`Node Recovery: ${computer.name} handshaked successfully.`);
      this.recalculateStats();
      this.notify();
    }, 5000);
  }

  getStigChecks(): StigCheck[] {
      return [
          { id: '1', vulnId: 'V-2200', title: 'WSUS server must use HTTPS.', severity: 'CAT I', status: 'Compliant', discussion: 'Ensures metadata and content are encrypted during transit to downstream nodes.' },
          { id: '2', vulnId: 'V-2101', title: 'SQL Server must have page verify set to CHECKSUM.', severity: 'CAT II', status: 'Compliant', discussion: 'Prevents database corruption from being propagated during I/O operations.' },
          { id: '3', vulnId: 'V-2554', title: 'Only approved classifications should be synchronized.', severity: 'CAT III', status: 'Open', discussion: 'Syncing unneeded drivers or feature packs bloats SUSDB unnecessarily.' },
          { id: '4', vulnId: 'V-9932', title: 'Database backups must be verified weekly.', severity: 'CAT II', status: 'Compliant', discussion: 'Recovery objectives depend on valid restorable backup artifacts.' }
      ];
  }
}

export const stateService = new StateService();
