import { expect, test } from '@playwright/test';

test('staff logs in and opens the owners list', async ({ page }) => {
  await page.route('**/api/web/auth/login', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(authPayload()),
    });
  });
  await page.route('**/api/web/auth/me', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(authPayload().user),
    });
  });
  await page.route('**/api/web/users', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 7,
          email: 'mario@example.com',
          first_name: 'Mario',
          last_name: 'Rossi',
          is_active: true,
          trip_count: 3,
          processed_trip_count: 2,
          latest_trip_started_at: '2026-08-30T10:00:00Z',
          total_distance_meters: 1250,
        },
      ]),
    });
  });

  await page.goto('/users');
  await expect(page).toHaveURL(/\/login\?next=/);

  await page.getByLabel('Email staff').fill('staff@example.com');
  await page.getByLabel('Password').fill('correct-password');
  await page.getByRole('button', { name: 'Accedi' }).click();

  await expect(page).toHaveURL(/\/users$/);
  await expect(page.getByRole('heading', { name: 'Utenti' })).toBeVisible();
  await expect(page.getByText('Mario Rossi')).toBeVisible();
  await expect(page.getByText('1.3 km')).toBeVisible();
});

function authPayload() {
  return {
    user: {
      id: 1,
      email: 'staff@example.com',
      first_name: 'Staff',
      last_name: 'Mobility',
      is_staff: true,
      is_superuser: false,
    },
    access_token: 'access-token',
    refresh_token: 'refresh-token',
    token_type: 'Bearer',
    access_expires_at: '2026-08-31T12:00:00Z',
    refresh_expires_at: '2026-09-07T12:00:00Z',
  };
}
