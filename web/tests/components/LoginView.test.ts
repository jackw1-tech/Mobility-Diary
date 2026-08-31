import { mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import LoginView from '../../src/views/LoginView.vue';
import { ApiError } from '../../src/services/apiClient';

const login = vi.fn();
const push = vi.fn();
const authState = reactive({ user: null, loading: false });

vi.mock('../../src/composables/useAuth', () => ({
  useAuth: () => ({ login, state: authState }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ query: { next: '/users' } }),
}));

describe('LoginView', () => {
  beforeEach(() => {
    login.mockReset();
    push.mockReset();
    authState.loading = false;
  });

  test('enables login only after both credentials are entered', async () => {
    const wrapper = mount(LoginView);
    const submit = wrapper.get('button[type="submit"]');
    expect(submit.attributes('disabled')).toBeDefined();

    await wrapper.get('input[name="email"]').setValue('staff@example.com');
    await wrapper.get('input[name="password"]').setValue('secret');
    expect(submit.attributes('disabled')).toBeUndefined();

    await wrapper.get('form').trigger('submit');

    expect(login).toHaveBeenCalledWith('staff@example.com', 'secret');
    expect(push).toHaveBeenCalledWith('/users');
  });

  test('announces authentication errors accessibly', async () => {
    login.mockRejectedValue(new ApiError('Credenziali non valide', 401));
    const wrapper = mount(LoginView);
    await wrapper.get('input[name="email"]').setValue('staff@example.com');
    await wrapper.get('input[name="password"]').setValue('wrong');

    await wrapper.get('form').trigger('submit');
    await Promise.resolve();

    const alert = wrapper.get('[role="alert"]');
    expect(alert.text()).toBe('Credenziali non valide');
  });
});
