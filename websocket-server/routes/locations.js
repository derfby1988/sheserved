'use strict';

/**
 * Routes: /api/locations/:userId
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api/locations.
 */

const express = require('express');
const {
  assertActorMatches,
  whenStrictRoute,
} = require('../middleware/auth');

/**
 * @param {{pool: object|null, locationsCache: Map, verifyTokenMw: Function}} deps
 */
function locationsRoutes({ pool, locationsCache, verifyTokenMw }) {
  const router = express.Router();

  // Get user's recent locations (REST API)
  router.get('/:userId', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.params.userId)), async (req, res) => {
    const { userId } = req.params;
    const limit = parseInt(req.query.limit) || 100;

    try {
      if (pool) {
        // Get from database
        const result = await pool.query(
          `SELECT * FROM locations 
           WHERE user_id = $1 
           ORDER BY created_at DESC 
           LIMIT $2`,
          [userId, limit]
        );
        res.json(result.rows);
      } else {
        // Get from in-memory cache
        const userLocations = locationsCache.get(userId) || [];
        const recentLocations = userLocations
          .slice(-limit)
          .reverse()
          .map((loc, index) => ({
            id: index + 1,
            ...loc,
          }));
        res.json(recentLocations);
      }
    } catch (error) {
      console.error('Error fetching locations:', error);
      res.status(500).json({ error: 'Failed to fetch locations' });
    }
  });

  return router;
}

module.exports = { locationsRoutes };
