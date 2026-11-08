import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  // GitHub Pages project-site path for https://allysonsantos90.github.io/assotck/
  base: '/assotck/',
  plugins: [react()],
});
