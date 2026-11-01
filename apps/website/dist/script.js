const languageButton = document.querySelector('#language-toggle');
const themeButton = document.querySelector('#theme-toggle');
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');

const pageMeta = {
  zh: {
    lang: 'zh-CN',
    title: 'iLaunchPad — 找回 LaunchPad',
    description: '为 macOS 26、27 带回 LaunchPad：原生液态玻璃、丝滑高刷交互、既有布局导入，以及仅 6.4 MB 的免费 MIT 开源应用。',
    button: 'EN'
  },
  en: {
    lang: 'en',
    title: 'iLaunchPad — Bring LaunchPad back',
    description: 'Bring LaunchPad back to macOS 26 and 27 with native Liquid Glass, fluid interaction, layout import, and a free 6.4 MB MIT-licensed app.',
    button: '中文'
  }
};

function setLanguage(language) {
  const next = pageMeta[language] ? language : 'zh';
  const meta = pageMeta[next];
  document.documentElement.lang = meta.lang;
  document.title = meta.title;
  document.querySelector('meta[name="description"]').content = meta.description;
  languageButton.textContent = meta.button;
  languageButton.setAttribute('aria-label', next === 'zh' ? 'Switch to English' : '切换到中文');
  updateThemeLabel();
  try { localStorage.setItem('ilaunchpad-site-language', next); } catch {}
}

function currentTheme() {
  return document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
}

function updateThemeLabel() {
  const dark = currentTheme() === 'dark';
  themeButton.textContent = dark ? '◑' : '◐';
  themeButton.setAttribute('aria-label', document.documentElement.lang === 'en'
    ? `Switch to ${dark ? 'light' : 'dark'} appearance`
    : `切换到${dark ? '浅色' : '深色'}外观`);
}

let savedTheme;
try { savedTheme = localStorage.getItem('ilaunchpad-site-theme'); } catch {}
if (savedTheme === 'light' || savedTheme === 'dark') document.documentElement.dataset.theme = savedTheme;

let initialLanguage = 'zh';
try { initialLanguage = localStorage.getItem('ilaunchpad-site-language') || 'zh'; } catch {}
setLanguage(initialLanguage);

languageButton.addEventListener('click', () => {
  setLanguage(document.documentElement.lang === 'en' ? 'zh' : 'en');
});

themeButton.addEventListener('click', () => {
  const next = currentTheme() === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem('ilaunchpad-site-theme', next); } catch {}
  updateThemeLabel();
});

function syncMediaMotion() {
  document.querySelectorAll('video[autoplay]').forEach((video) => {
    if (motionPreference.matches) video.pause();
    else video.play().catch(() => {});
  });
}

syncMediaMotion();
motionPreference.addEventListener?.('change', syncMediaMotion);
