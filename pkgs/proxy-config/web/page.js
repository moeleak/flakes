// The profile page: Material Web components, and the switches, which show the
// QR code and links of the variant they select (all of them are in the page).
// The type scale is not here: the server inlines typescale.css so the text
// has its final size before this script runs.
import '@material/web/button/filled-button.js';
import '@material/web/button/text-button.js';
import '@material/web/elevation/elevation.js';
import '@material/web/switch/switch.js';

const switches = [...document.querySelectorAll('md-switch[data-switch]')];

function show() {
  const on = switches.filter((s) => s.selected).map((s) => s.dataset.switch);
  const variant = on.join(',');
  for (const element of document.querySelectorAll('[data-variant]')) {
    element.hidden = element.dataset.variant !== variant;
  }
  const url = new URL(location.href);
  for (const s of switches) {
    if (s.selected) {
      url.searchParams.set(s.dataset.switch, 'true');
    } else {
      url.searchParams.delete(s.dataset.switch);
    }
  }
  history.replaceState(null, '', url);
}

for (const s of switches) {
  s.addEventListener('change', show);
}
