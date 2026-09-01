// =============================================================================
// WorkFromPhone — Interactive Website Scripts & Dynamic Release Fetcher
// =============================================================================

const GITHUB_REPO = 'xxparthparekhxx/workfromphone';

// Tab Switcher
function switchTab(evt, tabId) {
  const contents = document.querySelectorAll('.tab-content');
  contents.forEach((content) => content.classList.remove('active'));

  const buttons = document.querySelectorAll('.tab-btn');
  buttons.forEach((btn) => btn.classList.remove('active'));

  const target = document.getElementById(tabId);
  if (target) {
    target.classList.add('active');
  }

  if (evt && evt.currentTarget) {
    evt.currentTarget.classList.add('active');
  }
}

// Copy to Clipboard
function copySnippet(elementId, btn) {
  const el = document.getElementById(elementId);
  if (!el) return;
  const text = el.innerText || el.textContent;
  copyText(text.trim(), btn);
}

function copyText(text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    const originalText = btn.innerText || btn.textContent;
    btn.innerText = '✓ Copied!';
    btn.style.color = '#9ece6a';
    btn.style.borderColor = '#9ece6a';

    setTimeout(() => {
      btn.innerText = originalText;
      btn.style.color = '';
      btn.style.borderColor = '';
    }, 2000);
  }).catch((err) => {
    console.error('Failed to copy: ', err);
  });
}

// Format bytes to MB
function formatBytes(bytes) {
  if (!bytes) return 'N/A';
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Dynamically fetch latest release from GitHub API
async function fetchLatestRelease() {
  try {
    const res = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`);
    if (!res.ok) return;

    const data = await res.json();
    const tagName = data.tag_name || 'v0.1.0';
    const cleanVersion = tagName.replace(/^backend-/, '');

    // Update release badges & version labels
    const badge = document.getElementById('release-badge');
    if (badge) {
      badge.textContent = `🚀 Release ${cleanVersion} Available`;
    }

    const versionEls = document.querySelectorAll('.release-version');
    versionEls.forEach((el) => {
      el.textContent = cleanVersion;
    });

    // Update download buttons and sizes if available in assets
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
    console.warn('Could not query GitHub Releases API, fallback to default static links.', err);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  fetchLatestRelease();
});
