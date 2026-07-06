import { createRouter, createWebHistory } from 'vue-router';
import LoginView from './views/LoginView.vue';
import DashboardShell from './views/DashboardShell.vue';
import UsersListView from './views/UsersListView.vue';
import UserTripsView from './views/UserTripsView.vue';
import TripDashboardView from './views/TripDashboardView.vue';
import DailyDashboardView from './views/DailyDashboardView.vue';
import { authSession } from './services/authSession';

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: LoginView,
      meta: { public: true },
    },
    {
      path: '/',
      name: 'dashboard',
      component: DashboardShell,
      redirect: { name: 'users' },
      children: [
        {
          path: 'users',
          name: 'users',
          component: UsersListView,
        },
        {
          path: 'users/:userId',
          name: 'user-trips',
          component: UserTripsView,
        },
        {
          path: 'users/:userId/trips/:tripId',
          name: 'trip-dashboard',
          component: TripDashboardView,
        },
        {
          path: 'users/:userId/days/:day',
          name: 'daily-dashboard',
          component: DailyDashboardView,
        },
      ],
    },
    {
      path: '/:pathMatch(.*)*',
      redirect: '/',
    },
  ],
});

router.beforeEach((to) => {
  const isPublic = Boolean(to.meta.public);
  const isAuthenticated = authSession.hasTokens();

  if (!isPublic && !isAuthenticated) {
    return { name: 'login', query: { next: to.fullPath } };
  }

  if (to.name === 'login' && isAuthenticated) {
    return { name: 'dashboard' };
  }

  return true;
});
