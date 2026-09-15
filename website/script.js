// =============================================================================
// WorkFromPhone — Technical Site Scripts & GitHub Release Fetcher
// =============================================================================

const GITHUB_REPO = 'xxparthparekhxx/workfromphone';

// Tab Switcher
function switchTab(evt, tabId) {
  const panes = document.querySelectorAll('.tab-pane');
  panes.forEach((pane) => pane.classList.remove('active'));

  const buttons = document.querySelectorAll('.tab-item');
  buttons.forEach((btn) => btn.classList.remove('active'));

  const target = document.getElementById(tabId);
  if (target) {
    target.classList.add('active');
  }

  if (evt && evt.currentTarget) {
    evt.currentTarget.classList.add('active');
  }
}

// Copy snippet to clipboard
function copySnippet(elementId, btn) {
  const el = document.getElementById(elementId);
  if (!el) return;
  const text = el.innerText || el.textContent;
  copyText(text.trim(), btn);
}

function copyText(text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    const originalText = btn.innerText || btn.textContent;
    btn.innerText = 'Copied';
    btn.style.color = 'var(--accent-green)';
    btn.style.borderColor = 'var(--accent-green)';

    setTimeout(() => {
      btn.innerText = originalText;
      btn.style.color = '';
      btn.style.borderColor = '';
    }, 1800);
  }).catch((err) => {
    console.error('Failed to copy: ', err);
  });
}

// Format bytes
function formatBytes(bytes) {
  if (!bytes) return 'N/A';
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Dynamic release query
async function fetchLatestRelease() {
  try {
    const res = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`);
    if (!res.ok) return;

    const data = await res.json();
    const tagName = data.tag_name || 'v0.1.0';
    const cleanVersion = tagName.replace(/^backend-v?/, '');

    const topBadge = document.getElementById('top-version-badge');
    if (topBadge) {
      topBadge.textContent = `v${cleanVersion}`;
    }

    const versionEls = document.querySelectorAll('.release-version');
    versionEls.forEach((el) => {
      el.textContent = cleanVersion;
    });

    if (data.assets && Array.isArray(data.assets)) {
      const x86Asset = data.assets.find((a) => a.name.includes('x86_64'));
      if (x86Asset) {
        const btnX86 = document.getElementById('btn-download-x86_64');
        const sizeX86 = document.getElementById('size-x86_64');
        if (btnX86) btnX86.href = x86Asset.browser_download_url;
        if (sizeX86) sizeX86.textContent = formatBytes(x86Asset.size);
      }

      const armAsset = data.assets.find((a) => a.name.includes('aarch64'));
      if (armAsset) {
        const btnArm = document.getElementById('btn-download-aarch64');
        const sizeArm = document.getElementById('size-aarch64');
        if (btnArm) btnArm.href = armAsset.browser_download_url;
        if (sizeArm) sizeArm.textContent = formatBytes(armAsset.size);
      }

      const manifestAsset = data.assets.find((a) => a.name.includes('backend-manifest.json'));
      if (manifestAsset) {
        const btnManifest = document.getElementById('btn-download-manifest');
        if (btnManifest) btnManifest.href = manifestAsset.browser_download_url;
      }
    }
  } catch (err) {
    console.warn('Fallback to static links:', err);
  }
}

// Highlight the nav link for the section currently in view
function initScrollSpy() {
  const sections = document.querySelectorAll('main section[id]');
  const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');
  if (!sections.length || !navLinks.length) return;

  const setActive = (id) => {
    navLinks.forEach((link) => {
      link.classList.toggle('active-link', link.getAttribute('href') === `#${id}`);
    });
  };

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          setActive(entry.target.id);
        }
      });
    },
    { rootMargin: '-45% 0px -50% 0px', threshold: 0 }
  );

  sections.forEach((section) => observer.observe(section));
}

document.addEventListener('DOMContentLoaded', () => {
  fetchLatestRelease();
  initScrollSpy();
});
