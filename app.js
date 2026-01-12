const vibes = [
  "Sunny Focus",
  "Chill Builder",
  "Bold Explorer",
  "Gentle Reset",
  "Electric Groove",
  "Slow Morning",
  "Cozy Night",
  "Playful Sprint",
  "Calm Curiosity",
];

const snacks = [
  "Berry Yogurt",
  "Matcha Latte",
  "Citrus Sparkler",
  "Dark Chocolate",
  "Toast with Honey",
  "Spicy Popcorn",
  "Mango Smoothie",
  "Herb Tea",
  "Pretzel Mix",
];

const missions = [
  "Write down three wins from today.",
  "Send a thank-you text to someone.",
  "Take a 5-minute stretch break.",
  "Make a tiny plan for tomorrow.",
  "Declutter one small surface.",
  "Listen to one favorite song.",
  "Sketch a doodle with no goal.",
  "Pick one task to finish in 20 minutes.",
  "Step outside and take 10 deep breaths.",
];

const vibeEl = document.getElementById("vibe");
const snackEl = document.getElementById("snack");
const missionEl = document.getElementById("mission");
const listEl = document.getElementById("list");

const randomItem = (items) => items[Math.floor(Math.random() * items.length)];

const generateMix = () => {
  vibeEl.textContent = randomItem(vibes);
  snackEl.textContent = randomItem(snacks);
  missionEl.textContent = randomItem(missions);
};

const loadHistory = () => {
  const raw = localStorage.getItem("mojo-history");
  return raw ? JSON.parse(raw) : [];
};

const saveHistory = (history) => {
  localStorage.setItem("mojo-history", JSON.stringify(history));
};

const renderHistory = (history) => {
  listEl.innerHTML = "";

  if (history.length === 0) {
    const empty = document.createElement("li");
    empty.textContent = "No mixes saved yet. Hit save after you mix it up!";
    listEl.appendChild(empty);
    return;
  }

  history.forEach((entry) => {
    const item = document.createElement("li");
    item.textContent = `${entry.vibe} · ${entry.snack} · ${entry.mission}`;
    listEl.appendChild(item);
  });
};

const addMix = () => {
  const history = loadHistory();
  const entry = {
    vibe: vibeEl.textContent,
    snack: snackEl.textContent,
    mission: missionEl.textContent,
  };

  history.unshift(entry);
  saveHistory(history.slice(0, 6));
  renderHistory(loadHistory());
};

const clearHistory = () => {
  saveHistory([]);
  renderHistory([]);
};

document.getElementById("mix").addEventListener("click", generateMix);
document.getElementById("save").addEventListener("click", addMix);
document.getElementById("clear").addEventListener("click", clearHistory);

generateMix();
renderHistory(loadHistory());
