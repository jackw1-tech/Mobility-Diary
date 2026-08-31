import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import UsersListView from '../../src/views/UsersListView.vue';
import { ApiError } from '../../src/services/apiClient';
import { fetchUsers } from '../../src/services/usersApi';

vi.mock('../../src/services/usersApi', () => ({
  fetchUsers: vi.fn(),
}));

const fetchUsersMock = vi.mocked(fetchUsers);

function mountView() {
  return mount(UsersListView, {
    global: {
      stubs: {
        RouterLink: {
          props: ['to'],
          template: '<a><slot /></a>',
        },
      },
    },
  });
}

describe('UsersListView', () => {
  beforeEach(() => {
    fetchUsersMock.mockReset();
  });

  test('renders owners returned by the public users service', async () => {
    fetchUsersMock.mockResolvedValue([
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
    ]);

    const wrapper = mountView();
    await flushPromises();

    expect(wrapper.get('[role="table"]').attributes('aria-label')).toBe(
      'Utenti analizzabili',
    );
    expect(wrapper.text()).toContain('Mario Rossi');
    expect(wrapper.text()).toContain('mario@example.com');
    expect(wrapper.text()).toContain('1.3 km');
  });

  test('shows the backend error and retries on demand', async () => {
    fetchUsersMock
      .mockRejectedValueOnce(new ApiError('Sessione scaduta', 401))
      .mockResolvedValueOnce([]);

    const wrapper = mountView();
    await flushPromises();
    expect(wrapper.text()).toContain('Sessione scaduta');

    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(fetchUsersMock).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('Nessun utente analizzabile.');
  });
});
