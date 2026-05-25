const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY =
  process.env.SUPABASE_SERVICE_KEY ||
  process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = SUPABASE_URL && SUPABASE_SERVICE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  : null;

function _parseJsonList(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value.map((item) => item.toString());
  if (typeof value === 'string') {
    try {
      const decoded = JSON.parse(value);
      if (Array.isArray(decoded)) {
        return decoded.map((item) => item.toString());
      }
    } catch (_) {
      // Ignore malformed JSON and fall through to empty list
    }
  }
  return [];
}

function _normalizeSettings(row) {
  if (!row) return null;

  return {
    userId: row.user_id,
    isEnabled: row.is_enabled === true,
    releaseDelayMinutes: Number(row.release_delay_minutes || 5),
    enabledFields: _parseJsonList(row.enabled_fields),
    requireActiveResponder: row.require_active_responder !== false,
    requireMedicalProfession: row.require_medical_profession === true,
    requireVerified: row.require_verified === true,
    emergencyFallback: row.emergency_fallback === true,
    whitelistedUserIds: _parseJsonList(row.whitelisted_user_ids),
    consentGivenAt: row.consent_given_at || null,
    updatedAt: row.updated_at || null,
  };
}

function _normalizeDeadManCheckin(row) {
  if (!row) return null;

  return {
    userId: row.user_id,
    isEnabled: row.is_enabled === true,
    checkInIntervalMinutes: Number(row.check_in_interval_minutes || 720),
    lastCheckInAt: row.last_check_in_at || null,
    lastTriggeredAt: row.last_triggered_at || null,
    lastReminderAt: row.last_reminder_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function createReleaseSession({ patientId, incidentId, videoId }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }

  const resolvedIncidentId = incidentId || videoId || null;
  if (!patientId) {
    throw new Error('patientId is required');
  }

  const { data: settingsRow, error: settingsError } = await supabase
    .from('emergency_health_data_settings')
    .select('user_id, is_enabled, release_delay_minutes, enabled_fields, require_active_responder, require_medical_profession, require_verified, emergency_fallback, whitelisted_user_ids, consent_given_at, updated_at')
    .eq('user_id', patientId)
    .maybeSingle();

  if (settingsError) {
    throw new Error(`Failed to load emergency health settings: ${settingsError.message}`);
  }

  const settings = _normalizeSettings(settingsRow);
  if (!settings || !settings.isEnabled || !settings.consentGivenAt) {
    return {
      created: false,
      reason: !settings ? 'missing_settings' : 'disabled',
      session: null,
      settings,
    };
  }

  let existingSessionQuery = supabase
    .from('emergency_health_release_sessions')
    .select('id, incident_id, patient_id, release_delay_minutes, triggered_at, panic_cancelled_at, auto_released_at, released_fields, status, created_at, updated_at')
    .eq('patient_id', patientId)
    .order('created_at', { ascending: false })
    .limit(1);

  existingSessionQuery = resolvedIncidentId == null
    ? existingSessionQuery.is('incident_id', null)
    : existingSessionQuery.eq('incident_id', resolvedIncidentId);

  const { data: existingSession, error: existingError } = await existingSessionQuery.maybeSingle();

  if (existingError) {
    throw new Error(`Failed to check existing emergency session: ${existingError.message}`);
  }

  if (existingSession) {
    return {
      created: false,
      reason: 'existing',
      session: existingSession,
      settings,
    };
  }

  const now = new Date().toISOString();
  const payload = {
    incident_id: resolvedIncidentId,
    patient_id: patientId,
    release_delay_minutes: settings.releaseDelayMinutes,
    triggered_at: now,
    released_fields: settings.enabledFields,
    status: 'counting',
    created_at: now,
    updated_at: now,
  };

  const { data: sessionRow, error: insertError } = await supabase
    .from('emergency_health_release_sessions')
    .insert(payload)
    .select('id, incident_id, patient_id, release_delay_minutes, triggered_at, panic_cancelled_at, auto_released_at, released_fields, status, created_at, updated_at')
    .single();

  if (insertError) {
    throw new Error(`Failed to create emergency health session: ${insertError.message}`);
  }

  return {
    created: true,
    reason: 'created',
    session: sessionRow,
    settings,
  };
}

async function getEmergencyHealthSettings({ userId }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!userId) {
    throw new Error('userId is required');
  }

  const { data, error } = await supabase
    .from('emergency_health_data_settings')
    .select('user_id, is_enabled, release_delay_minutes, enabled_fields, require_active_responder, require_medical_profession, require_verified, emergency_fallback, whitelisted_user_ids, consent_given_at, created_at, updated_at')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load emergency health settings: ${error.message}`);
  }

  return _normalizeSettings(data);
}

async function upsertEmergencyHealthSettings({ userId, settings }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!userId) {
    throw new Error('userId is required');
  }

  const payload = {
    user_id: userId,
    is_enabled: settings?.isEnabled === true,
    release_delay_minutes: Number(settings?.releaseDelayMinutes || 5),
    enabled_fields: Array.isArray(settings?.enabledFields) ? settings.enabledFields.map((item) => item.toString()) : [],
    require_active_responder: settings?.requireActiveResponder !== false,
    require_medical_profession: settings?.requireMedicalProfession === true,
    require_verified: settings?.requireVerified === true,
    emergency_fallback: settings?.emergencyFallback === true,
    whitelisted_user_ids: Array.isArray(settings?.whitelistedUserIds) ? settings.whitelistedUserIds.map((item) => item.toString()) : [],
    consent_given_at: settings?.consentGivenAt || null,
    updated_at: new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from('emergency_health_data_settings')
    .upsert(payload, { onConflict: 'user_id' })
    .select('user_id, is_enabled, release_delay_minutes, enabled_fields, require_active_responder, require_medical_profession, require_verified, emergency_fallback, whitelisted_user_ids, consent_given_at, created_at, updated_at')
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to save emergency health settings: ${error.message}`);
  }

  return _normalizeSettings(data);
}

async function getDeadManCheckin({ userId }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!userId) {
    throw new Error('userId is required');
  }

  const { data, error } = await supabase
    .from('emergency_health_dead_man_checkins')
    .select('user_id, is_enabled, check_in_interval_minutes, last_check_in_at, last_triggered_at, last_reminder_at, created_at, updated_at')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load dead-man check-in state: ${error.message}`);
  }

  return _normalizeDeadManCheckin(data);
}

async function upsertDeadManCheckin({ userId, checkin }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!userId) {
    throw new Error('userId is required');
  }

  const payload = {
    user_id: userId,
    is_enabled: checkin?.isEnabled === true,
    check_in_interval_minutes: Number(checkin?.checkInIntervalMinutes || 720),
    last_check_in_at: checkin?.lastCheckInAt || null,
    last_triggered_at: checkin?.lastTriggeredAt || null,
    last_reminder_at: checkin?.lastReminderAt || null,
    updated_at: new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from('emergency_health_dead_man_checkins')
    .upsert(payload, { onConflict: 'user_id' })
    .select('user_id, is_enabled, check_in_interval_minutes, last_check_in_at, last_triggered_at, last_reminder_at, created_at, updated_at')
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to save dead-man check-in state: ${error.message}`);
  }

  return _normalizeDeadManCheckin(data);
}

async function updateDeadManCheckInTimestamp({ userId, checkInAt }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!userId) {
    throw new Error('userId is required');
  }

  const { data, error } = await supabase
    .from('emergency_health_dead_man_checkins')
    .update({
      last_check_in_at: (checkInAt || new Date()).toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', userId)
    .select('user_id, is_enabled, check_in_interval_minutes, last_check_in_at, last_triggered_at, last_reminder_at, created_at, updated_at')
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to update dead-man check-in timestamp: ${error.message}`);
  }

  return _normalizeDeadManCheckin(data);
}

async function getIncidentHealthData({ incidentId, responderId }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!incidentId) {
    throw new Error('incidentId is required');
  }
  if (!responderId) {
    throw new Error('responderId is required');
  }

  const now = new Date().toISOString();

  // 1. Validate responder has a valid access token for this incident
  const { data: tokenRow, error: tokenError } = await supabase
    .from('emergency_health_access_tokens')
    .select('id, session_id, responder_id, incident_id, expires_at, revoked_at')
    .eq('incident_id', incidentId)
    .eq('responder_id', responderId)
    .gt('expires_at', now)
    .is('revoked_at', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (tokenError) {
    throw new Error(`Token lookup failed: ${tokenError.message}`);
  }

  if (!tokenRow) {
    return {
      allowed: false,
      reason: 'no_valid_token',
      data: null,
    };
  }

  // 2. Get the session to verify it's released and get released_fields + patient_id
  const { data: sessionRow, error: sessionError } = await supabase
    .from('emergency_health_release_sessions')
    .select('id, incident_id, patient_id, status, released_fields, auto_released_at')
    .eq('id', tokenRow.session_id)
    .eq('status', 'released')
    .maybeSingle();

  if (sessionError) {
    throw new Error(`Session lookup failed: ${sessionError.message}`);
  }

  if (!sessionRow) {
    return {
      allowed: false,
      reason: 'session_not_released',
      data: null,
    };
  }

  const patientId = sessionRow.patient_id;
  const releasedFields = _parseJsonList(sessionRow.released_fields);

  // 3. Fetch patient basic info
  const { data: profile, error: profileError } = await supabase
    .from('consumer_profiles')
    .select('health_info, birthday, emergency_contact, emergency_phone')
    .eq('user_id', patientId)
    .maybeSingle();

  if (profileError) {
    throw new Error(`Profile lookup failed: ${profileError.message}`);
  }

  const { data: user, error: userError } = await supabase
    .from('users')
    .select('first_name, last_name, profile_image_url, phone')
    .eq('id', patientId)
    .maybeSingle();

  if (userError) {
    throw new Error(`User lookup failed: ${userError.message}`);
  }

  const result = {
    allowed: true,
    reason: 'ok',
    session: {
      id: sessionRow.id,
      incidentId: sessionRow.incident_id,
      patientId: sessionRow.patient_id,
      status: sessionRow.status,
      releasedFields,
      autoReleasedAt: sessionRow.auto_released_at,
    },
    patient: {
      name: [user?.first_name, user?.last_name].filter(Boolean).join(' ') || null,
      profileImageUrl: user?.profile_image_url || null,
      phone: user?.phone || null,
      birthday: profile?.birthday || null,
      emergencyContact: profile?.emergency_contact || null,
      emergencyPhone: profile?.emergency_phone || null,
    },
    healthData: {},
  };

  const healthInfo = profile?.health_info || {};

  // 4. Assemble health data based on released_fields
  if (releasedFields.includes('blood_type')) {
    result.healthData.bloodType = healthInfo['blood_type'] || null;
  }
  if (releasedFields.includes('allergies')) {
    result.healthData.allergies = healthInfo['allergies'] || null;
  }
  if (releasedFields.includes('chronic_conditions')) {
    result.healthData.chronicConditions = healthInfo['chronic_conditions'] || null;
  }
  if (releasedFields.includes('surgical_history')) {
    result.healthData.surgicalHistory = healthInfo['surgical_history'] || null;
  }
  if (releasedFields.includes('emergency_contact')) {
    result.healthData.emergencyContact = profile?.emergency_contact || null;
    result.healthData.emergencyPhone = profile?.emergency_phone || null;
  }

  // 5. Fetch related tables if fields are released
  if (releasedFields.includes('prescriptions')) {
    const { data: prescriptions } = await supabase
      .from('prescriptions')
      .select('id, medications, notes, status, issued_at')
      .eq('patient_id', patientId)
      .order('issued_at', { ascending: false })
      .limit(5);
    result.healthData.prescriptions = prescriptions || [];
  }

  if (releasedFields.includes('consultation_history')) {
    const { data: notes } = await supabase
      .from('consultation_notes')
      .select('id, consultation_id, provider_id, chief_complaint, diagnosis, treatment_plan, recommendations, created_at, follow_up_date')
      .eq('patient_id', patientId)
      .order('created_at', { ascending: false })
      .limit(5);
    result.healthData.consultationNotes = notes || [];
  }

  if (releasedFields.includes('device_metrics')) {
    const { data: metrics } = await supabase
      .from('device_health_metrics')
      .select('metric_type, value, unit, measured_at, source_name')
      .eq('user_id', patientId)
      .order('measured_at', { ascending: false })
      .limit(15);
    result.healthData.deviceMetrics = metrics || [];
  }

  if (releasedFields.includes('weight_history')) {
    const { data: weights } = await supabase
      .from('health_data_logs')
      .select('new_value, created_at')
      .eq('user_id', patientId)
      .eq('field_type', 'weight')
      .order('created_at', { ascending: false })
      .limit(10);
    result.healthData.weightHistory = (weights || []).map((row) => ({
      value: row.new_value?.toString().split(' ').first || null,
      unit: 'kg',
      measuredAt: row.created_at,
    }));
  }

  return result;
}

async function revokeActiveSessions({ patientId }) {
  if (!supabase) {
    throw new Error('Supabase service client is not configured');
  }
  if (!patientId) {
    throw new Error('patientId is required');
  }

  const now = new Date().toISOString();

  // 1. Find all counting sessions for this patient
  const { data: sessions, error: sessionError } = await supabase
    .from('emergency_health_release_sessions')
    .select('id, incident_id, status')
    .eq('patient_id', patientId)
    .eq('status', 'counting');

  if (sessionError) {
    throw new Error(`Failed to fetch active sessions: ${sessionError.message}`);
  }

  if (!sessions || sessions.length === 0) {
    return { revokedCount: 0, sessionIds: [] };
  }

  const sessionIds = sessions.map((s) => s.id);

  // 2. Cancel the sessions
  const { error: updateError } = await supabase
    .from('emergency_health_release_sessions')
    .update({
      status: 'cancelled',
      panic_cancelled_at: now,
      updated_at: now,
    })
    .in('id', sessionIds)
    .eq('status', 'counting');

  if (updateError) {
    throw new Error(`Failed to cancel sessions: ${updateError.message}`);
  }

  // 3. Revoke any tokens for these sessions
  const { error: revokeError } = await supabase
    .from('emergency_health_access_tokens')
    .update({ revoked_at: now })
    .in('session_id', sessionIds)
    .is('revoked_at', null);

  if (revokeError) {
    throw new Error(`Failed to revoke tokens: ${revokeError.message}`);
  }

  return { revokedCount: sessions.length, sessionIds };
}

module.exports = {
  createReleaseSession,
  getEmergencyHealthSettings,
  upsertEmergencyHealthSettings,
  getDeadManCheckin,
  upsertDeadManCheckin,
  updateDeadManCheckInTimestamp,
  getIncidentHealthData,
  revokeActiveSessions,
};
