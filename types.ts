
export enum HealthStatus {
  HEALTHY = 'Healthy',
  WARNING = 'Warning',
  CRITICAL = 'Critical',
  UNKNOWN = 'Unknown'
}

export enum UpdateClass {
  SECURITY = 'Security Updates',
  CRITICAL = 'Critical Updates',
  DEFINITIONS = 'Definition Updates',
  FEATURE = 'Feature Packs',
  DRIVERS = 'Drivers'
}

export enum LogLevel {
  INFO = 'INFO',
  WARNING = 'WARNING',
  ERROR = 'ERROR'
}

export interface StigCheck {
  id: string;
  vulnId: string;
  title: string;
  severity: 'CAT I' | 'CAT II' | 'CAT III';
  status: 'Open' | 'Not_Applicable' | 'Compliant';
  discussion: string;
}

export interface LogEntry {
  id: string;
  timestamp: string;
  level: LogLevel;
  message: string;
  context?: any;
}

export interface ScheduledTask {
  id: string;
  name: string;
  trigger: 'Daily' | 'Weekly' | 'Monthly';
  time: string;
  status: 'Ready' | 'Running' | 'Disabled';
  lastRun: string;
  nextRun: string;
}

export interface ServiceState {
  name: string;
  status: 'Running' | 'Stopped' | 'Pending';
  lastCheck: string;
  type: 'WSUS' | 'SQL' | 'IIS';
}

export interface DatabaseMetrics {
  currentSizeGB: number;
  maxSizeGB: number;
  instanceName: string;
  contentPath: string;
  lastBackup: string;
}

export interface WsusComputer {
  id: string;
  name: string;
  ipAddress: string;
  os: string;
  status: HealthStatus;
  lastSync: string;
  updatesNeeded: number;
  updatesInstalled: number;
  targetGroup: string;
}

export interface WsusUpdate {
  id: string;
  title: string;
  classification: UpdateClass;
  kbArticle: string;
  arrivalDate: string;
  status: 'Approved' | 'Declined' | 'Not Approved';
  complianceRate: number;
}

export interface EnvironmentStats {
  totalComputers: number;
  healthyComputers: number;
  warningComputers: number;
  criticalComputers: number;
  totalUpdates: number;
  securityUpdatesCount: number;
  services: ServiceState[];
  db: DatabaseMetrics;
  isInstalled: boolean;
  diskFreeGB: number;
  automationStatus: 'Ready' | 'Not Set' | 'Running';
}

export interface OperationParameter {
  id: string;
  label: string;
  type: 'select' | 'number' | 'text';
  options?: string[];
  defaultValue: any;
}

export interface Operation {
  id: string;
  name: string;
  description: string;
  module: string;
  category: 'Deployment' | 'Maintenance' | 'Recovery' | 'Security';
  script: string;
  modeRequirement?: 'Online' | 'Air-Gap' | 'Both';
  parameters?: OperationParameter[];
  isDatabaseOp?: boolean;
}
