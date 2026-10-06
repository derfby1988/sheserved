'use strict';

/**
 * Incident Overview Map service (VIDEO_SYSTEM_PLAN.md §22.4)
 *
 * Pure logic (validation, bucketing, clustering, photo capping, cursor) is
 * separated from data access so unit tests can cover the contract without
 * PostgreSQL/Redis. Data access has two paths with identical response shape:
 *   1. Local PostgreSQL (canonical, same first-GPS-point rule as the
 *      emergency list: earliest video_gps_tracks by timestamp_offset)
 *   2. Supabase RPC `get_emergency_incident_map` fallback — fail-closed:
 *      if neither path can honor the category/viewport contract the caller
 *      gets an error, never an unfiltered response.
 *
 * Response shape (both paths):
 * {
 *   mode: 'points' | 'clusters',
 *   zoom, truncated,
 *   legend: { red, orange, gold, gray, black, total },
 *   excluded: { noUsableCoordinate, invalidTime },
 *   items: [ point | cluster ],
 *   nextCursor: string|null   (points mode only)
 * }
 */

const {
    bucketForCreatedAt,
    isValidCoordinate,
} = require('./incident-map-policy');

const ZOOM_MIN = 0;
const ZOOM_MAX = 22;
const POINTS_ZOOM_THRESHOLD = 12; // zoom >= 12 → individual points
const DEFAULT_PAGE_LIMIT = 300;
const MAX_PAGE_LIMIT = 500;
const MAX_CLUSTER_INPUT = 20_000; // safety cap before clustering
const PHOTOS_PER_POINT = 3;

// ──────────────────────────────────────────────────────────────
// Query parsing / validation (server is authoritative — §22.4.2)
// ──────────────────────────────────────────────────────────────

function _badRequest(message) {
    const err = new Error(message);
    err.statusCode = 400;
    return err;
}

/**
 * @param {{category_id?:string, bounds?:string, zoom?:string, cursor?:string, limit?:string}} query
 */
function parseMapQuery(query) {
    const categoryId = typeof query.category_id === 'string' ? query.category_id.trim() : '';
    if (!/^[0-9a-fA-F-]{36}$/.test(categoryId)) {
        throw _badRequest('category_id must be a UUID');
    }

    const rawBounds = typeof query.bounds === 'string' ? query.bounds.trim() : '';
    const parts = rawBounds.split(',').map((s) => s.trim());
    if (parts.length !== 4 || parts.some((p) => p.length === 0)) {
        throw _badRequest('bounds must be "south,west,north,east"');
    }
    const [south, west, north, east] = parts.map(Number);
    for (const v of [south, west, north, east]) {
        if (!Number.isFinite(v)) throw _badRequest('bounds values must be finite numbers');
    }
    if (south < -90 || south > 90 || north < -90 || north > 90) {
        throw _badRequest('bounds latitude out of range');
    }
    if (west < -180 || west > 180 || east < -180 || east > 180) {
        throw _badRequest('bounds longitude out of range');
    }
    if (south > north || west > east) {
        throw _badRequest('bounds must satisfy south<=north and west<=east');
    }

    const zoom = Number(query.zoom);
    if (!Number.isFinite(zoom) || !Number.isInteger(zoom) || zoom < ZOOM_MIN || zoom > ZOOM_MAX) {
        throw _badRequest(`zoom must be an integer between ${ZOOM_MIN} and ${ZOOM_MAX}`);
    }

    let limit = DEFAULT_PAGE_LIMIT;
    if (query.limit !== undefined && query.limit !== '') {
        limit = Number(query.limit);
        if (!Number.isFinite(limit) || !Number.isInteger(limit) || limit < 1 || limit > MAX_PAGE_LIMIT) {
            throw _badRequest(`limit must be an integer between 1 and ${MAX_PAGE_LIMIT}`);
        }
    }

    const cursor = typeof query.cursor === 'string' && query.cursor.length > 0 ? query.cursor : null;

    return {
        categoryId,
        bounds: { south, west, north, east },
        zoom,
        limit,
        cursor,
        mode: zoom >= POINTS_ZOOM_THRESHOLD ? 'points' : 'clusters',
    };
}

// ──────────────────────────────────────────────────────────────
// Cursor (opaque, base64url JSON of the sort key: created_at + id)
// ──────────────────────────────────────────────────────────────

function encodeCursor(row) {
    return Buffer.from(
        JSON.stringify({ c: new Date(row.created_at).toISOString(), i: String(row.id) }),
    ).toString('base64url');
}

function decodeCursor(cursor) {
    try {
        const obj = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
        if (typeof obj !== 'object' || obj === null) return null;
        if (typeof obj.c !== 'string' || typeof obj.i !== 'string') return null;
        if (!Number.isFinite(Date.parse(obj.c))) return null;
        if (!/^[0-9a-fA-F-]{36}$/.test(obj.i)) return null;
        return { createdAt: obj.c, id: obj.i };
    } catch (_) {
        return null;
    }
}

// ──────────────────────────────────────────────────────────────
// Pure row → response building
// ──────────────────────────────────────────────────────────────

/**
 * Validate + bucket raw incident rows.
 * Expected row shape: { id, category_id, created_at, latitude, longitude }
 * (latitude/longitude may be null when the video has no GPS track).
 * Rows without a usable canonical coordinate or with an invalid/future
 * `created_at` are dropped here; the aggregate query reports their counts.
 */
function normalizeIncidentRows(rows, nowMs) {
    const points = [];
    for (const row of rows || []) {
        const lat = row.latitude === null || row.latitude === undefined ? null : Number(row.latitude);
        const lng = row.longitude === null || row.longitude === undefined ? null : Number(row.longitude);
        if (lat === null || lng === null || !isValidCoordinate(lat, lng)) continue;
        const bucket = bucketForCreatedAt(row.created_at, nowMs);
        if (bucket === null) continue;
        points.push({
            id: String(row.id),
            categoryId: String(row.category_id),
            createdAt: new Date(row.created_at).toISOString(),
            bucket,
            lat,
            lng,
            photos: [],
        });
    }
    return points;
}

/** Grid-cluster points at [zoom]; cell size halves per zoom level. */
function clusterPoints(points, zoom) {
    const cellDeg = 180 / Math.pow(2, zoom);
    const cells = new Map();
    for (const p of points) {
        const key = `${Math.floor(p.lat / cellDeg)}:${Math.floor(p.lng / cellDeg)}`;
        let cell = cells.get(key);
        if (!cell) {
            cell = { latSum: 0, lngSum: 0, count: 0, byBucket: { red: 0, orange: 0, gold: 0, gray: 0, black: 0 } };
            cells.set(key, cell);
        }
        cell.latSum += p.lat;
        cell.lngSum += p.lng;
        cell.count++;
        cell.byBucket[p.bucket]++;
    }
    return [...cells.values()].map((c) => ({
        kind: 'cluster',
        lat: c.latSum / c.count,
        lng: c.lngSum / c.count,
        count: c.count,
        byBucket: c.byBucket,
    }));
}

/** Attach ≤ PHOTOS_PER_POINT completed photos per point (gallery order). */
function attachPhotos(points, photoRows) {
    const byVideo = new Map();
    for (const row of photoRows || []) {
        const videoId = String(row.video_id);
        let list = byVideo.get(videoId);
        if (!list) {
            list = [];
            byVideo.set(videoId, list);
        }
        if (list.length < PHOTOS_PER_POINT) {
            list.push({
                id: String(row.id),
                url: typeof row.photo_url === 'string' ? row.photo_url : '',
                createdAt: new Date(row.created_at).toISOString(),
            });
        }
    }
    for (const p of points) {
        p.photos = byVideo.get(p.id) || [];
    }
    return points;
}

function _legendFromCounts(c) {
    const red = Number(c.red) || 0;
    const orange = Number(c.orange) || 0;
    const gold = Number(c.gold) || 0;
    const gray = Number(c.gray) || 0;
    const black = Number(c.black) || 0;
    return { red, orange, gold, gray, black, total: red + orange + gold + gray + black };
}

/**
 * Build the final response.
 * @param {'points'|'clusters'} mode
 * @param {Array} points validated points for THIS response (clusters: whole
 *   viewport set; points: the current page, photos already attached)
 * @param {{red,orange,gold,gray,black,invalidTime,noUsableCoordinate}} agg
 *   aggregate over the whole viewport (from SQL/RPC)
 */
function buildResponse({ mode, zoom, points, agg, truncated = false, hasMore = false, lastRow = null }) {
    const legend = _legendFromCounts(agg);
    const base = {
        mode,
        zoom,
        legend,
        excluded: {
            noUsableCoordinate: Number(agg.noUsableCoordinate) || 0,
            invalidTime: Number(agg.invalidTime) || 0,
        },
        truncated,
        items: [],
        nextCursor: null,
    };

    if (mode === 'clusters') {
        base.items = clusterPoints(points, zoom);
        return base;
    }

    base.items = points.map((p) => ({
        kind: 'point',
        id: p.id,
        categoryId: p.categoryId,
        createdAt: p.createdAt,
        bucket: p.bucket,
        lat: p.lat,
        lng: p.lng,
        photos: p.photos,
    }));
    if (hasMore && lastRow) {
        base.nextCursor = encodeCursor(lastRow);
    }
    return base;
}

// ──────────────────────────────────────────────────────────────
// Data access — Local PostgreSQL
// ──────────────────────────────────────────────────────────────

// Canonical location = FIRST gps track by timestamp_offset (same rule as the
// emergency list subquery), via index-friendly LATERAL instead of DISTINCT ON.
// Cursor pagination on (created_at DESC, id DESC) — row-value comparison.
const POINTS_PAGE_SQL = `
    SELECT v.id, v.category_id, v.created_at, t.latitude, t.longitude
    FROM videos v
    CROSS JOIN LATERAL (
        SELECT t.latitude, t.longitude
        FROM video_gps_tracks t
        WHERE t.video_id = v.id
        ORDER BY t.timestamp_offset ASC
        LIMIT 1
    ) t
    WHERE v.type IN ('emergency', 'emergency_photo')
      AND v.category_id = $1::uuid
      AND t.latitude IS NOT NULL AND t.longitude IS NOT NULL
      AND t.latitude BETWEEN $2 AND $4
      AND t.longitude BETWEEN $3 AND $5
      AND ($6::timestamptz IS NULL OR (v.created_at, v.id) < ($6::timestamptz, $7::uuid))
    ORDER BY v.created_at DESC, v.id DESC
    LIMIT $8
`;

// Full viewport set for cluster mode (no pagination; capped by caller).
const VIEWPORT_ROWS_SQL = `
    SELECT v.id, v.category_id, v.created_at, t.latitude, t.longitude
    FROM videos v
    CROSS JOIN LATERAL (
        SELECT t.latitude, t.longitude
        FROM video_gps_tracks t
        WHERE t.video_id = v.id
        ORDER BY t.timestamp_offset ASC
        LIMIT 1
    ) t
    WHERE v.type IN ('emergency', 'emergency_photo')
      AND v.category_id = $1::uuid
      AND t.latitude IS NOT NULL AND t.longitude IS NOT NULL
      AND t.latitude BETWEEN $2 AND $4
      AND t.longitude BETWEEN $3 AND $5
    ORDER BY v.created_at DESC, v.id DESC
    LIMIT $6
`;

// Viewport aggregate (legend + invalidTime) + category-wide no-coordinate
// count. Bucket CASE mirrors incident-map-policy.js exactly (contiguous,
// inclusive upper bounds; future/NULL created_at is never bucketed).
const VIEWPORT_AGG_SQL = `
    WITH first_point AS (
        SELECT v.id, v.created_at, t.latitude, t.longitude
        FROM videos v
        CROSS JOIN LATERAL (
            SELECT t.latitude, t.longitude
            FROM video_gps_tracks t
            WHERE t.video_id = v.id
            ORDER BY t.timestamp_offset ASC
            LIMIT 1
        ) t
        WHERE v.type IN ('emergency', 'emergency_photo')
          AND v.category_id = $1::uuid
    )
    SELECT
        COUNT(*) FILTER (WHERE fp.age <= interval '24 hours') AS red,
        COUNT(*) FILTER (WHERE fp.age >  interval '24 hours' AND fp.age <= interval '7 days') AS orange,
        COUNT(*) FILTER (WHERE fp.age >  interval '7 days'  AND fp.age <= interval '35 days') AS gold,
        COUNT(*) FILTER (WHERE fp.age >  interval '35 days' AND fp.age <= interval '365 days') AS gray,
        COUNT(*) FILTER (WHERE fp.age >  interval '365 days') AS black,
        COUNT(*) FILTER (WHERE fp.age IS NULL) AS invalid_time,
        (
            SELECT COUNT(*) FROM videos v2
            WHERE v2.type IN ('emergency', 'emergency_photo')
              AND v2.category_id = $1::uuid
              AND NOT EXISTS (
                  SELECT 1 FROM (
                      SELECT t.latitude, t.longitude
                      FROM video_gps_tracks t
                      WHERE t.video_id = v2.id
                      ORDER BY t.timestamp_offset ASC
                      LIMIT 1
                  ) c
                  WHERE c.latitude IS NOT NULL AND c.longitude IS NOT NULL
                    AND c.latitude BETWEEN -90 AND 90
                    AND c.longitude BETWEEN -180 AND 180
                    AND (c.latitude <> 0 OR c.longitude <> 0)
              )
        ) AS no_usable_coordinate
    FROM (
        SELECT CASE
            WHEN fp.created_at IS NULL OR fp.created_at > now() THEN NULL
            ELSE now() - fp.created_at
        END AS age
        FROM first_point fp
        WHERE fp.latitude IS NOT NULL AND fp.longitude IS NOT NULL
          AND fp.latitude BETWEEN $2 AND $4
          AND fp.longitude BETWEEN $3 AND $5
    ) fp
`;

const PHOTOS_SQL = `
    SELECT video_id, id, photo_url, created_at
    FROM thai_mhung_photos
    WHERE video_id = ANY($1::uuid[]) AND blur_status = 'completed'
    ORDER BY video_id, created_at DESC, id DESC
    LIMIT $2
`;

async function fetchIncidentMapLocal(pool, params, nowMs) {
    const { categoryId, bounds, zoom, limit, cursor, mode } = params;
    const b = [bounds.south, bounds.west, bounds.north, bounds.east];

    const aggRows = await pool.query(VIEWPORT_AGG_SQL, [categoryId, ...b]);
    const r = aggRows.rows[0] || {};
    // SQL returns snake_case — map to the camelCase contract once, here.
    const agg = {
        red: r.red,
        orange: r.orange,
        gold: r.gold,
        gray: r.gray,
        black: r.black,
        invalidTime: r.invalid_time,
        noUsableCoordinate: r.no_usable_coordinate,
    };

    if (mode === 'clusters') {
        const rowsResult = await pool.query(VIEWPORT_ROWS_SQL, [
            categoryId, ...b, MAX_CLUSTER_INPUT,
        ]);
        const points = normalizeIncidentRows(rowsResult.rows, nowMs);
        return buildResponse({
            mode,
            zoom,
            points,
            agg,
            truncated: rowsResult.rows.length >= MAX_CLUSTER_INPUT,
        });
    }

    // points mode — fetch limit+1 rows to detect hasMore
    const cursorKey = cursor ? decodeCursor(cursor) : null;
    if (cursor && !cursorKey) throw _badRequest('cursor is invalid');
    const rowsResult = await pool.query(POINTS_PAGE_SQL, [
        categoryId, ...b,
        cursorKey ? cursorKey.createdAt : null,
        cursorKey ? cursorKey.id : null,
        limit + 1,
    ]);
    const hasMore = rowsResult.rows.length > limit;
    const pageRows = hasMore ? rowsResult.rows.slice(0, limit) : rowsResult.rows;
    const points = normalizeIncidentRows(pageRows, nowMs);

    if (points.length > 0) {
        const photoRows = await pool.query(PHOTOS_SQL, [
            points.map((p) => p.id),
            points.length * PHOTOS_PER_POINT,
        ]);
        attachPhotos(points, photoRows.rows);
    }

    return buildResponse({
        mode,
        zoom,
        points,
        agg,
        hasMore,
        lastRow: hasMore ? pageRows[pageRows.length - 1] : null,
    });
}

// ──────────────────────────────────────────────────────────────
// Data access — Supabase RPC fallback (same shape, fail-closed)
// ──────────────────────────────────────────────────────────────

async function fetchIncidentMapSupabase(supabase, params) {
    if (!supabase) throw new Error('Supabase fallback unavailable');
    const { categoryId, bounds, zoom, limit, cursor, mode } = params;
    const cursorKey = cursor ? decodeCursor(cursor) : null;
    if (cursor && !cursorKey) throw _badRequest('cursor is invalid');
    const { data, error } = await supabase.rpc('get_emergency_incident_map', {
        p_category_id: categoryId,
        p_south: bounds.south,
        p_west: bounds.west,
        p_north: bounds.north,
        p_east: bounds.east,
        p_zoom: zoom,
        p_cursor_created_at: cursorKey ? cursorKey.createdAt : null,
        p_cursor_id: cursorKey ? cursorKey.id : null,
        p_limit: limit,
    });
    if (error) throw new Error(`Supabase incident map RPC failed: ${error.message}`);
    if (!data || typeof data !== 'object') throw new Error('Supabase incident map RPC returned no data');
    // The RPC returns the same shape; normalize numeric strings just in case.
    data.legend = _legendFromCounts(data.legend || {});
    data.excluded = {
        noUsableCoordinate: Number(data.excluded?.noUsableCoordinate) || 0,
        invalidTime: Number(data.excluded?.invalidTime) || 0,
    };
    return data;
}

/**
 * Orchestrator: Local first, Supabase fallback on local failure.
 * @returns {Promise<object>} response (see module doc)
 */
async function fetchIncidentMap({ pool, supabase, params, nowMs = Date.now() }) {
    try {
        return await fetchIncidentMapLocal(pool, params, nowMs);
    } catch (localError) {
        console.error('[IncidentMap] local query failed:', localError.message);
        return fetchIncidentMapSupabase(supabase, params);
    }
}

module.exports = {
    ZOOM_MIN,
    ZOOM_MAX,
    POINTS_ZOOM_THRESHOLD,
    DEFAULT_PAGE_LIMIT,
    MAX_PAGE_LIMIT,
    MAX_CLUSTER_INPUT,
    PHOTOS_PER_POINT,
    parseMapQuery,
    encodeCursor,
    decodeCursor,
    normalizeIncidentRows,
    clusterPoints,
    attachPhotos,
    buildResponse,
    fetchIncidentMapLocal,
    fetchIncidentMapSupabase,
    fetchIncidentMap,
    POINTS_PAGE_SQL,
    VIEWPORT_ROWS_SQL,
    VIEWPORT_AGG_SQL,
    PHOTOS_SQL,
};
