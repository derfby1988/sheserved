const { createClient } = require('@supabase/supabase-js');
const emergencyHealthSessionService = require('./emergency-health-session-service');
const socketService = require('./socket-service');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY =
  process.env.SUPABASE_SERVICE_KEY ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_ANON_KEY;

const supabase = SUPABASE_URL && SUPABASE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_KEY)
  : null;

const CHECK_INTERVAL_MS = parseInt(process.env.EMERGENCY_HEALTH_MONITOR_INTERVAL_MS || '300000', 10);
const SENSOR_RECENCY_MINUTES = parseInt(process.env.EMERGENCY_HEALTH_SENSOR_RECENCY_MINUTES || '45', 10);
const SENSOR_COOLDOWN_MINUTES = parseInt(process.env.EMERGENCY_HEALTH_SENSOR_COOLDOWN_MINUTES || '60', 10);

let _intervalHandle = null;
let _isRunning = false;

function start() {
  if (_intervalHandle) {
    console.warn('[EmergencyHealthMonitor] Already running — skipping start()');
    return;
  }

  if (!supabase) {
    console.warn('[EmergencyHealthMonitor] Supabase not configured — monitor disabled');
    return;
  }

  console.log(
    `[EmergencyHealthMonitor] Started (interval=${CHECK_INTERVAL_MS / 1000}s, sensor_cooldown=${SENSOR_COOLDOWN_MINUTES}m)`
  );

  void _runCheck();
  _intervalHandle = setInterval(() => void _runCheck(), CHECK_INTERVAL_MS);
}

function stop() {
  if (_intervalHandle) {
    clearInterval(_intervalHandle);
    _intervalHandle = null;
    console.log('[EmergencyHealthMonitor] Stopped');
  }
}

async function runOnce() {
  await _runCheck();
}

async function _runCheck() {
  if (_isRunning || !supabase) return;
  _isRunning = true;
  const now = new Date();
  try {
    await Promise.all([
      _checkSensorAnomalies(now),
      _checkDeadManSwitches(now),
    ]);
  } catch (error) {
    console.error('[EmergencyHealthMonitor] Check failed:', error?.message || error);
  } finally {
    _isRunning = false;
  }
}

async function _checkSensorAnomalies(now) {
  const { data: users, error } = await supabase
    .from('emergency_health_data_settings')
    .select('user_id')
    .eq('is_enabled', true)
    .not('consent_given_at', 'is', null);

  if (error) {
    console.error('[EmergencyHealthMonitor] Failed to load settings:', error.message);
    return;
  }

  if (!Array.isArray(users) || users.length === 0) return;

  for (const row of users) {
    const userId = row?.user_id;
    if (!userId) continue;

    const metrics = await _fetchMetricSet(userId);
    const reasons = _buildSensorReactions(metrics, now);
    if (reasons.length === 0) continue;

    const hasRecentRelease = await _hasRecentRelease(userId, now);
    if (hasRecentRelease) continue;

    await _triggerSensorRelease(userId, reasons, metrics);
  }
}

function _buildSensorReactions(metrics, now) {
  const recencyMs = SENSOR_RECENCY_MINUTES * 60 * 1000;
  const reasons = [];

  if (_isRecent(metrics.heartRateAt, now, recencyMs)) {
    if (metrics.heartRate != null && (metrics.heartRate >= 150 || metrics.heartRate <= 40)) {
      reasons.push('อัตราการเต้นหัวใจผิดปกติ');
    }
  }

  if (_isRecent(metrics.bloodOxygenAt, now, recencyMs)) {
    if (metrics.bloodOxygen != null && metrics.bloodOxygen <= 91) {
      reasons.push('ค่าออกซิเจนในเลือดต่ำ');
    }
  }

  if (_isRecent(metrics.hrvAt, now, recencyMs)) {
    if (metrics.hrv != null && metrics.hrv <= 15) {
      reasons.push('HRV ต่ำผิดปกติ');
    }
  }

  return reasons;
}

function _isRecent(measuredAt, now, windowMs) {
  if (!measuredAt) return false;
  const measured = new Date(measuredAt);
  const delta = now.getTime() - measured.getTime();
  return delta >= 0 && delta <= windowMs;
}

async function _fetchMetricSet(userId) {
  const heartRate = await _fetchLatestMetric(userId, 'heart_rate');
  const bloodOxygen = await _fetchLatestMetric(userId, 'blood_oxygen');
  const hrv = await _fetchLatestMetric(userId, 'hrv_sdnn');

  return {
    heartRate: heartRate?.value,
    heartRateAt: heartRate?.measuredAt,
    bloodOxygen: bloodOxygen?.value,
    bloodOxygenAt: bloodOxygen?.measuredAt,
    hrv: hrv?.value,
    hrvAt: hrv?.measuredAt,
  };
}

async function _fetchLatestMetric(userId, metricType) {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from('device_health_metrics')
    .select('value, measured_at')
    .eq('user_id', userId)
    .eq('metric_type', metricType)
    .order('measured_at', { ascending: false })
    .limit(1);

  if (error) {
    console.error(`[EmergencyHealthMonitor] Failed to fetch metric ${metricType} for ${userId}:`, error.message);
    return null;
  }

  if (!Array.isArray(data) || data.length === 0) return null;
  const row = data[0];
  return {
    value: row?.value != null ? Number(row.value) : null,
    measuredAt: row?.measured_at,
  };
}

async function _hasRecentRelease(userId, now) {
  if (!supabase) return false;
  const cutoff = new Date(now.getTime() - SENSOR_COOLDOWN_MINUTES * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from('emergency_health_release_sessions')
    .select('id')
    .eq('patient_id', userId)
    .gte('triggered_at', cutoff)
    .order('triggered_at', { ascending: false })
    .limit(1);

  if (error) {
    console.error('[EmergencyHealthMonitor] Failed to check cooldown:', error.message);
    return false;
  }

  return Array.isArray(data) && data.length > 0;
}

async function _triggerSensorRelease(userId, reasons, metrics) {
  try {
    const result = await emergencyHealthSessionService.createReleaseSession({
      patientId: userId,
      incidentId: null,
    });

    socketService.broadcastEmergencyHealthSensorAlert(userId, {
      reasons,
      metrics,
      sessionId: result?.session?.id ?? null,
      status: result?.reason,
      triggeredAt: result?.session?.triggered_at,
    });

    console.log(`[EmergencyHealthMonitor] Sensor alert triggered for user=${userId} reasons=${reasons.join(', ')}`);
  } catch (error) {
    console.error('[EmergencyHealthMonitor] Failed to trigger sensor release:', error?.message || error);
  }
}

async function _checkDeadManSwitches(now) {
  if (!supabase) return;
  const { data: rows, error } = await supabase
    .from('emergency_health_dead_man_checkins')
    .select('id, user_id, check_in_interval_minutes, last_check_in_at, last_triggered_at, last_reminder_at, created_at')
    .eq('is_enabled', true);

  if (error) {
    console.error('[EmergencyHealthMonitor] Failed to load dead man rows:', error.message);
    return;
  }

  if (!Array.isArray(rows) || rows.length === 0) return;

  for (const row of rows) {
    const userId = row?.user_id;
    if (!userId) continue;

    const intervalMinutes = row.check_in_interval_minutes ?? 720;
    const base = row.last_check_in_at || row.created_at;
    const baseTime = base ? new Date(base) : now;
    const deadline = new Date(baseTime.getTime() + intervalMinutes * 60 * 1000);
    const lastTriggered = row.last_triggered_at ? new Date(row.last_triggered_at) : null;

    if (deadline <= now && (!lastTriggered || lastTriggered.getTime() < deadline.getTime())) {
      await _triggerDeadManRelease(row, now, intervalMinutes);
      continue;
    }

    const reminderMarginMinutes = Math.min(60, Math.max(15, Math.floor(intervalMinutes / 3)));
    const reminderDue = new Date(deadline.getTime() - reminderMarginMinutes * 60 * 1000);
    const lastReminder = row.last_reminder_at ? new Date(row.last_reminder_at) : null;

    if (reminderDue <= now && (!lastReminder || lastReminder.getTime() < reminderDue.getTime())) {
      await _sendDeadManReminder(row, reminderDue);
    }
  }
}

async function _triggerDeadManRelease(row, now, intervalMinutes) {
  try {
    await emergencyHealthSessionService.createReleaseSession({
      patientId: row.user_id,
      incidentId: null,
    });

    await supabase
      .from('emergency_health_dead_man_checkins')
      .update({
        last_triggered_at: now.toISOString(),
        updated_at: now.toISOString(),
      })
      .eq('id', row.id);

    socketService.broadcastEmergencyHealthDeadManTriggered(row.user_id, {
      nextCheckInAt: new Date(now.getTime() + intervalMinutes * 60 * 1000).toISOString(),
    });

    console.log(`[EmergencyHealthMonitor] Dead man switch triggered for user=${row.user_id}`);
  } catch (error) {
    console.error('[EmergencyHealthMonitor] Dead man trigger failed:', error?.message || error);
  }
}

async function _sendDeadManReminder(row, reminderTime) {
  if (!supabase) return;
  const nowIso = new Date().toISOString();
  await supabase
    .from('emergency_health_dead_man_checkins')
    .update({ last_reminder_at: nowIso, updated_at: nowIso })
    .eq('id', row.id);

  socketService.broadcastEmergencyHealthDeadManReminder(row.user_id, {
    reminderFor: reminderTime.toISOString(),
    intervalMinutes: row.check_in_interval_minutes ?? 720,
  });

  console.log(`[EmergencyHealthMonitor] Dead man reminder sent for user=${row.user_id}`);
}

module.exports = {
  start,
  stop,
  runOnce,
  isRunning: () => _intervalHandle != null,
};
