// The profile page: Material Web components, and the Tailscale switch, which
// shows the QR code and links of the other variant (both are in the page).
// The type scale is not here: the server inlines typescale.css so the text
// has its final size before this script runs.
import '@material/web/button/filled-button.js';
import '@material/web/button/text-button.js';
import '@material/web/elevation/elevation.js';
import '@material/web/switch/switch.js';

const toggle = document.getElementById('tailscale');

function show(tailscale) {
  const variant = tailscale ? 'tailscale' : 'plain';
  for (const element of document.querySelectorAll('[data-variant]')) {
    element.hidden = element.dataset.variant !== variant;
  }
  const url = new URL(location.href);
  if (tailscale) {
    url.searchParams.set('tailscale', 'true');
  } else {
    url.searchParams.delete('tailscale');
  }
  history.replaceState(null, '', url);
}

toggle.addEventListener('change', () => show(toggle.selected));
