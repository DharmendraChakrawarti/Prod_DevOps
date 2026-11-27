import axios from 'axios';

// In production & local:
// 1. If VITE_API_BASE_URL is explicitly passed, use it.
// 2. Otherwise default to relative '/api' which Nginx proxies internally to the backend!
// 3. If running via Vite dev server directly (localhost:5173), fallback to localhost:8080/api.
const envApiUrl = import.meta.env.VITE_API_BASE_URL;
const isViteDev = window.location.port === '5173';
const defaultApiUrl = isViteDev ? 'http://localhost:8080/api' : '/api';

const api = axios.create({
  baseURL: envApiUrl || defaultApiUrl,
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    // If the server returns 401 or 403 (invalid token, user deleted, etc.), clear the token and redirect to login
    if (error.response && (error.response.status === 401 || error.response.status === 403)) {
      if (localStorage.getItem('token')) {
        localStorage.removeItem('token');
        localStorage.removeItem('user');
        window.dispatchEvent(new Event('authChange'));
        // Optional redirect to login, but firing authChange helps the app re-render
        if(window.location.pathname !== '/login' && window.location.pathname !== '/register' && window.location.pathname !== '/') {
            window.location.href = '/login';
        }
      }
    }
    return Promise.reject(error);
  }
);

export default api;
