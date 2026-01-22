
import { LogEntry, LogLevel } from '../types';

const STORAGE_KEY = 'wsus_pro_logs';
const MAX_LOGS = 200;

class LoggingService {
  private logs: LogEntry[] = [];

  constructor() {
    this.loadFromStorage();
  }

  private loadFromStorage() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        this.logs = JSON.parse(saved);
      }
    } catch (e) {
      console.error('Failed to load logs', e);
      this.logs = [];
    }
  }

  private persist() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.logs.slice(-MAX_LOGS)));
    } catch (e) {
      console.error('Failed to persist logs', e);
    }
  }

  private log(level: LogLevel, message: string, context?: any) {
    const entry: LogEntry = {
      id: Math.random().toString(36).substr(2, 9),
      timestamp: new Date().toISOString(),
      level,
      message,
      context
    };
    
    this.logs.push(entry);
    this.persist();
    
    // Dispatch event for UI updates if active
    window.dispatchEvent(new CustomEvent('wsus_log_added', { detail: entry }));
    
    if (level === LogLevel.ERROR) {
      console.error(`[WSUS ${level}] ${message}`, context);
    }
  }

  info(message: string, context?: any) {
    this.log(LogLevel.INFO, message, context);
  }

  warn(message: string, context?: any) {
    this.log(LogLevel.WARNING, message, context);
  }

  error(message: string, context?: any) {
    this.log(LogLevel.ERROR, message, context);
  }

  getLogs(): LogEntry[] {
    return [...this.logs].reverse();
  }

  clearLogs() {
    this.logs = [];
    localStorage.removeItem(STORAGE_KEY);
    window.dispatchEvent(new CustomEvent('wsus_log_cleared'));
  }
}

export const loggingService = new LoggingService();
