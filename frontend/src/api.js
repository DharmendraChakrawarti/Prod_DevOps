import axios from 'axios';

// In production / containerized environments:
// 1. If VITE_API_BASE_URL is passed at build time (e.g. backend LoadBalancer URL), use it.
// 2. Otherwise default to current hostname on port 8080.
const envApiUrl = import.meta.env.VITE_API_BASE_URL;
const defaultApiUrl = `http://${window.location.hostname}:8080/api`;

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
