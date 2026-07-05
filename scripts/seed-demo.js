#!/usr/bin/env node
/**
 * seed-demo.js — Seeds the demo_reviews table with a sample review.
 * Run once after `docker compose up` to populate demo data.
 *
 * Usage: node scripts/seed-demo.js
 * Requires: PostgreSQL running on localhost:5432
 */

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/ai_pr_reviewer',
});

const DEMO_REVIEW = {
  pr_title: 'feat: add error handling for database connection',
  pr_url: 'https://github.com/demo/repo/pull/42',
  model_used: 'gpt-4o',
  review_json: JSON.stringify({
    overall_score: 78,
    verdict: 'needs_work',
    summary: 'Good start on adding database error handling. The pattern is correct but there are several areas that need attention: missing context propagation, inconsistent error wrapping, and a potential nil pointer dereference in the fallback path.',
    files: [
      {
        path: 'internal/database/conn.go',
        score: 70,
        issues: [
          { line: 42, severity: 'critical', message: 'Missing context propagation: db.QueryContext should be used instead of db.Query to support cancellation and timeouts' },
          { line: 55, severity: 'warning', message: 'Error is shadowed by the := assignment; use = instead to capture the original error' },
        ],
        positive: ['Good use of prepared statements', 'Connection pooling configured correctly'],
      },
      {
        path: 'internal/database/middleware.go',
        score: 85,
        issues: [
          { line: 28, severity: 'info', message: 'Consider adding retry logic with exponential backoff for transient failures' },
        ],
        positive: ['Clean middleware pattern', 'Proper defer of rollback on error'],
      },
    ],
    positive_observations: [
      'Consistent error handling pattern across the package',
      'Good separation of concerns between connection management and query execution',
      'Proper use of sql.ErrNoRows checks',
    ],
    missing_tests: [
      'Test connection timeout behavior',
      'Test context cancellation propagation',
      'Test concurrent connection handling',
    ],
    metrics: { total_issues: 3, critical: 1, warning: 1, info: 1 },
  }),
};

async function seed() {
  const client = await pool.connect();
  try {
    // Deactivate all existing demos
    await client.query('UPDATE demo_reviews SET is_active = FALSE WHERE is_active = TRUE');

    // Insert new demo
    await client.query(
      `INSERT INTO demo_reviews (pr_title, pr_url, review_json, model_used, is_active)
       VALUES ($1, $2, $3::jsonb, $4, TRUE)`,
      [DEMO_REVIEW.pr_title, DEMO_REVIEW.pr_url, DEMO_REVIEW.review_json, DEMO_REVIEW.model_used]
    );

    console.log('✓ Demo review seeded successfully');
  } catch (err) {
    console.error('✗ Seed failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

seed();
