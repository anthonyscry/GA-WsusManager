
import { HealthStatus, UpdateClass, WsusComputer, WsusUpdate, EnvironmentStats } from '../types';

export const mockComputers: WsusComputer[] = [
  {
    id: '1',
    name: 'SRV-DC-01',
    ipAddress: '10.0.0.10',
    os: 'Windows Server 2022',
    status: HealthStatus.HEALTHY,
    lastSync: '2023-10-24 09:15',
    updatesNeeded: 0,
    updatesInstalled: 45,
    targetGroup: 'Domain Controllers'
  },
  {
    id: '2',
    name: 'WKS-DEV-05',
    ipAddress: '10.0.0.105',
    os: 'Windows 11 Pro',
    status: HealthStatus.WARNING,
    lastSync: '2023-10-23 14:22',
    updatesNeeded: 3,
    updatesInstalled: 112,
    targetGroup: 'Workstations'
  },
  {
    id: '3',
    name: 'SRV-SQL-02',
    ipAddress: '10.0.0.22',
    os: 'Windows Server 2019',
    status: HealthStatus.CRITICAL,
    lastSync: '2023-10-21 02:00',
    updatesNeeded: 12,
    updatesInstalled: 88,
    targetGroup: 'Databases'
  }
];

export const mockUpdates: WsusUpdate[] = [
  {
    id: 'kb1',
    title: '2023-10 Cumulative Update for Windows 11',
    classification: UpdateClass.SECURITY,
    kbArticle: 'KB5031354',
    arrivalDate: '2023-10-10',
    status: 'Approved',
    complianceRate: 85
  }
];

export const mockStats: EnvironmentStats = {
  totalComputers: 142,
  healthyComputers: 128,
  warningComputers: 10,
  criticalComputers: 4,
  totalUpdates: 524,
  securityUpdatesCount: 42,
  isInstalled: true,
  diskFreeGB: 62,
  automationStatus: 'Ready',
  services: [
    { name: 'WSUS Service', status: 'Running', lastCheck: '1 min ago', type: 'WSUS' },
    { name: 'SQL Server (Express)', status: 'Running', lastCheck: '2 mins ago', type: 'SQL' },
    { name: 'IIS (W3SVC)', status: 'Running', lastCheck: '1 min ago', type: 'IIS' }
  ],
  db: {
    currentSizeGB: 8.42,
    maxSizeGB: 10,
    instanceName: 'localhost\\SQLEXPRESS',
    contentPath: 'C:\\WSUS\\',
    lastBackup: '2023-10-23 04:00'
  }
};
