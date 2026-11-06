import '@fontsource/ibm-plex-mono/400.css';
import '@fontsource/instrument-sans/400.css';
import '@fontsource/instrument-sans/500.css';
import '@fontsource/instrument-sans/600.css';
import './style.css';
import { boot } from './app';

const root = document.querySelector<HTMLElement>('#app');
if (root) {
  boot(root).catch((err: unknown) => {
    root.replaceChildren();
    const note = document.createElement('div');
    note.className = 'boot';
    note.textContent = err instanceof Error ? err.message : 'The measured surface could not be read.';
    root.appendChild(note);
  });
}
