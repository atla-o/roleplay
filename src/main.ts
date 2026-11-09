import '@fontsource/ibm-plex-mono/400.css';
import '@fontsource/instrument-sans/400.css';
import '@fontsource/instrument-sans/500.css';
import '@fontsource/instrument-sans/600.css';
import './style.css';
import { start } from './shell';

const root = document.querySelector<HTMLElement>('#app');
if (root) {
  start(root).catch((err: unknown) => {
    root.replaceChildren();
    const note = document.createElement('div');
    note.className = 'boot';
    note.textContent = err instanceof Error ? err.message : 'The world map could not be opened.';
    root.appendChild(note);
  });
}
