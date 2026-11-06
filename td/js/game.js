/**
 * Volam Outpost — TD + roguelike vertical slice
 * Reuses Project Volam Kenney monster/skill sprites from ../assets
 */

const TILE = 40;
const COLS = 24;
const ROWS = 13;
const MAX_WAVES = 8;
const START_LIVES = 20;
const START_GOLD = 175;
let nextId = 1;
function uid() {
  return `id-${nextId++}`;
}

/** Path as tile coordinates (centers used for movement). */
const PATH_TILES = [
  [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6],
  [5, 5], [5, 4], [5, 3], [5, 2],
  [6, 2], [7, 2], [8, 2], [9, 2], [10, 2],
  [10, 3], [10, 4], [10, 5], [10, 6], [10, 7], [10, 8],
  [11, 8], [12, 8], [13, 8], [14, 8],
  [14, 7], [14, 6], [14, 5], [14, 4],
  [15, 4], [16, 4], [17, 4], [18, 4],
  [18, 5], [18, 6], [18, 7], [18, 8], [18, 9], [18, 10],
  [19, 10], [20, 10], [21, 10], [22, 10], [23, 10],
];

const ASSET = {
  slime: "../assets/monsters/slime.png",
  rat: "../assets/monsters/rat.png",
  spider: "../assets/monsters/spider.png",
  bat: "../assets/monsters/bat.png",
  crawler: "../assets/monsters/crawler.png",
  archer: "../assets/monsters/archer.png",
  fireball: "../assets/skills/fireball.png",
  ice: "../assets/skills/ice_shard.png",
  pierce: "../assets/skills/pierce.png",
  nova: "../assets/skills/nova.png",
  focus: "../assets/skills/focus.png",
  bloom: "../assets/skills/bloom.png",
  burst: "../assets/skills/burst.png",
  meteor: "../assets/skills/meteor.png",
};

const TOWER_DEFS = {
  archer: {
    id: "archer",
    name: "Archer",
    desc: "Fast single-target shots",
    cost: 45,
    range: 2.75,
    damage: 14,
    rate: 0.65,
    color: "#8fbf5c",
    projectile: "arrow",
    icon: ASSET.pierce,
  },
  mage: {
    id: "mage",
    name: "Ember Mage",
    desc: "AoE fire bursts",
    cost: 70,
    range: 2.35,
    damage: 20,
    rate: 1.05,
    splash: 1.0,
    color: "#d4653a",
    projectile: "fire",
    icon: ASSET.fireball,
  },
  frost: {
    id: "frost",
    name: "Frost Totem",
    desc: "Slows enemies on hit",
    cost: 60,
    range: 2.5,
    damage: 9,
    rate: 0.85,
    slow: 0.5,
    slowDur: 1.8,
    color: "#5a9bb8",
    projectile: "ice",
    icon: ASSET.ice,
  },
};

const ENEMY_DEFS = {
  slime: { hp: 40, speed: 48, reward: 8, sprite: ASSET.slime, scale: 1 },
  rat: { hp: 28, speed: 78, reward: 7, sprite: ASSET.rat, scale: 0.95 },
  spider: { hp: 70, speed: 55, reward: 12, sprite: ASSET.spider, scale: 1.05 },
  bat: { hp: 35, speed: 95, reward: 9, sprite: ASSET.bat, scale: 0.9 },
  crawler: { hp: 140, speed: 38, reward: 18, sprite: ASSET.crawler, scale: 1.15 },
  archer: { hp: 90, speed: 52, reward: 14, sprite: ASSET.archer, scale: 1.05 },
};

/** Wave composition. */
const WAVES = [
  { delay: 0.85, spawns: [["slime", 6]] },
  { delay: 0.65, spawns: [["slime", 5], ["rat", 5]] },
  { delay: 0.55, spawns: [["rat", 7], ["spider", 4]] },
  { delay: 0.5, spawns: [["bat", 8], ["slime", 5]] },
  { delay: 0.5, spawns: [["spider", 7], ["crawler", 2]] },
  { delay: 0.42, spawns: [["bat", 7], ["archer", 4], ["rat", 5]] },
  { delay: 0.4, spawns: [["crawler", 3], ["spider", 7], ["bat", 6]] },
  { delay: 0.35, spawns: [["crawler", 4], ["archer", 6], ["spider", 7], ["bat", 8]] },
];

const SKILL_POOL = [
  {
    id: "sharp_tips",
    name: "Sharp Tips",
    body: "+25% tower damage",
    icon: ASSET.pierce,
    apply: (s) => { s.dmgMul *= 1.25; },
  },
  {
    id: "longshot",
    name: "Longshot",
    body: "+20% tower range",
    icon: ASSET.focus,
    apply: (s) => { s.rangeMul *= 1.2; },
  },
  {
    id: "rapid_fire",
    name: "Rapid Fire",
    body: "+20% attack speed",
    icon: ASSET.burst,
    apply: (s) => { s.rateMul *= 0.8; },
  },
  {
    id: "bounty",
    name: "Bounty Hunter",
    body: "+35% gold from kills",
    icon: ASSET.bloom,
    apply: (s) => { s.goldMul *= 1.35; },
  },
  {
    id: "fortify",
    name: "Fortify Gate",
    body: "+5 lives immediately",
    icon: ASSET.nova,
    apply: (s) => { s.lives += 5; },
  },
  {
    id: "war_chest",
    name: "War Chest",
    body: "+80 gold now",
    icon: ASSET.meteor,
    apply: (s) => { s.gold += 80; },
  },
  {
    id: "multishot",
    name: "Multishot",
    body: "Towers hit +1 extra target",
    icon: ASSET.pierce,
    apply: (s) => { s.extraTargets += 1; },
  },
  {
    id: "deep_freeze",
    name: "Deep Freeze",
    body: "Slow effects 40% stronger",
    icon: ASSET.ice,
    apply: (s) => { s.slowMul *= 1.4; },
  },
  {
    id: "ember_core",
    name: "Ember Core",
    body: "+40% splash radius (mages)",
    icon: ASSET.fireball,
    apply: (s) => { s.splashMul *= 1.4; },
  },
];

const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");
const overlay = document.getElementById("overlay");
const overlayCard = document.getElementById("overlay-card");

const ui = {
  lives: document.getElementById("stat-lives"),
  gold: document.getElementById("stat-gold"),
  wave: document.getElementById("stat-wave"),
  kills: document.getElementById("stat-kills"),
  picker: document.getElementById("tower-picker"),
  selection: document.getElementById("selection-info"),
  skillList: document.getElementById("skill-list"),
  upgrade: document.getElementById("btn-upgrade"),
  sell: document.getElementById("btn-sell"),
  start: document.getElementById("btn-start"),
  speed: document.getElementById("btn-speed"),
  restart: document.getElementById("btn-restart"),
};

const images = {};
let pathSet = new Set();
let pathPoints = [];
let buildable = new Set();

const state = {
  lives: START_LIVES,
  gold: START_GOLD,
  wave: 0,
  kills: 0,
  phase: "build", // build | combat | pick | won | lost
  speed: 1,
  selectedBuild: "archer",
  selectedTower: null,
  towers: [],
  enemies: [],
  projectiles: [],
  particles: [],
  spawnQueue: [],
  spawnTimer: 0,
  skills: [],
  mods: blankMods(),
  hoverTile: null,
  time: 0,
  shake: 0,
};

function blankMods() {
  return {
    lives: 0,
    gold: 0,
    dmgMul: 1,
    rangeMul: 1,
    rateMul: 1,
    goldMul: 1,
    slowMul: 1,
    splashMul: 1,
    extraTargets: 0,
  };
}

function key(c, r) {
  return `${c},${r}`;
}

function tileCenter(c, r) {
  return { x: c * TILE + TILE / 2, y: r * TILE + TILE / 2 };
}

function loadImages() {
  const urls = new Set(Object.values(ASSET));
  return Promise.all(
    [...urls].map(
      (src) =>
        new Promise((resolve) => {
          const img = new Image();
          img.onload = () => {
            images[src] = img;
            resolve();
          };
          img.onerror = () => {
            console.warn("Missing asset", src);
            resolve();
          };
          img.src = src;
        })
    )
  );
}

function buildPathGeometry() {
  pathSet = new Set(PATH_TILES.map(([c, r]) => key(c, r)));
  pathPoints = PATH_TILES.map(([c, r]) => tileCenter(c, r));
  buildable = new Set();
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      if (pathSet.has(key(c, r))) continue;
      // Keep a soft border around the path for readability but allow adjacent builds
      buildable.add(key(c, r));
    }
  }
}

function resetRun() {
  state.lives = START_LIVES;
  state.gold = START_GOLD;
  state.wave = 0;
  state.kills = 0;
  state.phase = "build";
  state.speed = 1;
  state.selectedBuild = "archer";
  state.selectedTower = null;
  state.towers = [];
  state.enemies = [];
  state.projectiles = [];
  state.particles = [];
  state.spawnQueue = [];
  state.spawnTimer = 0;
  state.skills = [];
  state.mods = blankMods();
  state.time = 0;
  state.shake = 0;
  hideOverlay();
  refreshTowerButtons();
  refreshSkills();
  refreshSelection();
  syncHud();
  ui.start.disabled = false;
  ui.start.textContent = "Start wave";
  ui.speed.textContent = "Speed ×1";
  showIntro();
}

function showIntro() {
  overlayCard.innerHTML = `
    <h2>Hold the Outpost</h2>
    <p>Place towers along the trail, upgrade them with gold, and pick a skill after each wave.
    Clear all <strong>${MAX_WAVES} waves</strong> without letting the gate fall.</p>
    <div class="overlay-actions">
      <button class="btn primary" id="intro-go" type="button">Begin</button>
    </div>
  `;
  overlay.classList.remove("hidden");
  const go = () => hideOverlay();
  document.getElementById("intro-go").onclick = go;
  overlay.onclick = (ev) => {
    if (ev.target === overlay) go();
  };
}

function hideOverlay() {
  overlay.classList.add("hidden");
  overlayCard.innerHTML = "";
}

function syncHud() {
  ui.lives.textContent = String(state.lives);
  ui.gold.textContent = String(Math.floor(state.gold));
  ui.wave.textContent = `${Math.min(state.wave, MAX_WAVES)} / ${MAX_WAVES}`;
  ui.kills.textContent = String(state.kills);
}

function refreshTowerButtons() {
  ui.picker.innerHTML = "";
  for (const def of Object.values(TOWER_DEFS)) {
    const btn = document.createElement("button");
    btn.className = "tower-btn" + (state.selectedBuild === def.id ? " active" : "");
    btn.type = "button";
    btn.innerHTML = `
      <img src="${def.icon}" alt="" width="36" height="36" />
      <span>
        <span class="name">${def.name}</span><br />
        <span class="desc">${def.desc}</span>
      </span>
      <span class="cost">${def.cost}g</span>
    `;
    btn.onclick = () => {
      state.selectedBuild = def.id;
      state.selectedTower = null;
      refreshTowerButtons();
      refreshSelection();
    };
    ui.picker.appendChild(btn);
  }
}

function refreshSkills() {
  if (!state.skills.length) {
    ui.skillList.classList.add("muted");
    ui.skillList.innerHTML = "<li>No skills yet — pick after waves.</li>";
    return;
  }
  ui.skillList.classList.remove("muted");
  ui.skillList.innerHTML = state.skills
    .map((id) => {
      const sk = SKILL_POOL.find((s) => s.id === id);
      return `<li><strong>${sk.name}</strong> — ${sk.body}</li>`;
    })
    .join("");
}

function towerStats(tower) {
  const def = TOWER_DEFS[tower.type];
  const lvl = tower.level;
  const dmg = Math.round(def.damage * (1 + 0.55 * (lvl - 1)) * state.mods.dmgMul);
  const range = def.range * (1 + 0.12 * (lvl - 1)) * state.mods.rangeMul;
  const rate = def.rate * Math.pow(0.88, lvl - 1) * state.mods.rateMul;
  const upgradeCost = Math.round(def.cost * (0.7 + 0.45 * lvl));
  return { def, dmg, range, rate, upgradeCost, maxLevel: 3 };
}

function refreshSelection() {
  const t = state.selectedTower;
  if (!t) {
    ui.selection.className = "selection muted";
    ui.selection.textContent = "Nothing selected — choose a tower type, then click a grass tile.";
    ui.upgrade.disabled = true;
    ui.sell.disabled = true;
    return;
  }
  const { def, dmg, range, rate, upgradeCost, maxLevel } = towerStats(t);
  ui.selection.className = "selection";
  ui.selection.innerHTML = `
    <strong>${def.name}</strong> · Lv ${t.level}/${maxLevel}<br />
    Dmg ${dmg} · Range ${range.toFixed(1)} · Rate ${rate.toFixed(2)}s
    ${def.splash ? `<br />Splash ${(def.splash * state.mods.splashMul).toFixed(2)}` : ""}
    ${def.slow ? `<br />Slow ${(def.slow * state.mods.slowMul * 100).toFixed(0)}%` : ""}
  `;
  ui.upgrade.disabled = state.phase === "pick" || t.level >= maxLevel || state.gold < upgradeCost;
  ui.upgrade.textContent = t.level >= maxLevel ? "Max level" : `Upgrade (${upgradeCost}g)`;
  ui.sell.disabled = state.phase === "combat" || state.phase === "pick";
}

function placeTower(c, r) {
  if (state.phase !== "build" && state.phase !== "combat") return;
  const k = key(c, r);
  if (!buildable.has(k) || pathSet.has(k)) return;
  if (state.towers.some((t) => t.c === c && t.r === r)) {
    state.selectedTower = state.towers.find((t) => t.c === c && t.r === r);
    state.selectedBuild = null;
    refreshTowerButtons();
    refreshSelection();
    return;
  }
  if (!state.selectedBuild) return;
  const def = TOWER_DEFS[state.selectedBuild];
  if (state.gold < def.cost) {
    pulseHud("gold");
    return;
  }
  state.gold -= def.cost;
  const tower = {
    id: uid(),
    type: def.id,
    c,
    r,
    level: 1,
    cooldown: 0,
    ...tileCenter(c, r),
  };
  state.towers.push(tower);
  state.selectedTower = tower;
  spawnParticles(tower.x, tower.y, def.color, 10);
  syncHud();
  refreshSelection();
}

function upgradeSelected() {
  const t = state.selectedTower;
  if (!t) return;
  const { upgradeCost, maxLevel } = towerStats(t);
  if (t.level >= maxLevel || state.gold < upgradeCost) return;
  state.gold -= upgradeCost;
  t.level += 1;
  spawnParticles(t.x, t.y, "#d4a84b", 14);
  syncHud();
  refreshSelection();
}

function sellSelected() {
  const t = state.selectedTower;
  if (!t || state.phase === "combat") return;
  const spent = TOWER_DEFS[t.type].cost + [...Array(t.level - 1)].reduce((sum, _, i) => {
    return sum + Math.round(TOWER_DEFS[t.type].cost * (0.7 + 0.45 * (i + 1)));
  }, 0);
  state.gold += Math.floor(spent * 0.5);
  state.towers = state.towers.filter((x) => x !== t);
  state.selectedTower = null;
  syncHud();
  refreshSelection();
}

function pulseHud(which) {
  const el = which === "gold" ? ui.gold : ui.lives;
  el.style.color = varDanger();
  setTimeout(() => {
    el.style.color = "";
  }, 250);
}

function varDanger() {
  return getComputedStyle(document.documentElement).getPropertyValue("--danger").trim() || "#c4473a";
}

function startWave() {
  if (state.phase !== "build") return;
  if (state.wave >= MAX_WAVES) return;
  state.wave += 1;
  const wave = WAVES[state.wave - 1];
  state.spawnQueue = [];
  for (const [type, count] of wave.spawns) {
    for (let i = 0; i < count; i++) state.spawnQueue.push(type);
  }
  state.spawnTimer = 0.15;
  state.phase = "combat";
  ui.start.disabled = true;
  ui.start.textContent = `Wave ${state.wave}…`;
  syncHud();
  refreshSelection();
}

function spawnEnemy(type) {
  const def = ENEMY_DEFS[type];
  const waveScale = 1 + (state.wave - 1) * 0.18;
  state.enemies.push({
    id: uid(),
    type,
    hp: def.hp * waveScale,
    maxHp: def.hp * waveScale,
    speed: def.speed,
    reward: Math.round(def.reward * (1 + (state.wave - 1) * 0.08)),
    progress: 0,
    slow: 0,
    slowTimer: 0,
    x: pathPoints[0].x,
    y: pathPoints[0].y,
  });
}

function enemyPos(enemy) {
  const max = pathPoints.length - 1;
  const t = Math.min(Math.max(enemy.progress, 0), max);
  const i = Math.floor(t);
  const f = t - i;
  const a = pathPoints[i];
  const b = pathPoints[Math.min(i + 1, max)];
  return {
    x: a.x + (b.x - a.x) * f,
    y: a.y + (b.y - a.y) * f,
  };
}

function dist(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.hypot(dx, dy);
}

function findTargets(tower, rangePx, count) {
  const scored = [];
  for (const e of state.enemies) {
    const p = enemyPos(e);
    const d = dist(tower, p);
    if (d <= rangePx) scored.push({ e, d, progress: e.progress });
  }
  scored.sort((a, b) => b.progress - a.progress || a.d - b.d);
  return scored.slice(0, count).map((s) => s.e);
}

function fireTower(tower, targets) {
  const { def, dmg, range } = towerStats(tower);
  for (const target of targets) {
    const p = enemyPos(target);
    state.projectiles.push({
      x: tower.x,
      y: tower.y,
      tx: p.x,
      ty: p.y,
      targetId: target.id,
      speed: def.projectile === "fire" ? 320 : 420,
      damage: dmg,
      splash: (def.splash || 0) * state.mods.splashMul * TILE,
      slow: (def.slow || 0) * state.mods.slowMul,
      slowDur: def.slowDur || 0,
      color: def.color,
      kind: def.projectile,
      life: 1.2,
    });
  }
  spawnParticles(tower.x, tower.y - 8, def.color, 3);
}

function applyHit(proj, enemy) {
  enemy.hp -= proj.damage;
  if (proj.slow > 0) {
    enemy.slow = Math.max(enemy.slow, proj.slow);
    enemy.slowTimer = Math.max(enemy.slowTimer, proj.slowDur);
  }
  spawnParticles(enemy.x, enemy.y, proj.color, 6);
  if (proj.splash > 0) {
    for (const other of state.enemies) {
      if (other === enemy) continue;
      const op = enemyPos(other);
      if (dist({ x: enemy.x, y: enemy.y }, op) <= proj.splash) {
        other.hp -= proj.damage * 0.55;
        if (proj.slow > 0) {
          other.slow = Math.max(other.slow, proj.slow * 0.7);
          other.slowTimer = Math.max(other.slowTimer, proj.slowDur * 0.7);
        }
      }
    }
  }
}

function killEnemy(enemy) {
  state.kills += 1;
  state.gold += Math.round(enemy.reward * state.mods.goldMul);
  spawnParticles(enemy.x, enemy.y, "#d4a84b", 12);
}

function leakEnemy(enemy) {
  state.lives -= 1;
  state.shake = 0.35;
  pulseHud("lives");
  spawnParticles(pathPoints.at(-1).x, pathPoints.at(-1).y, "#c4473a", 16);
  if (state.lives <= 0) {
    state.lives = 0;
    endLose();
  }
}

function endLose() {
  state.phase = "lost";
  ui.start.disabled = true;
  overlayCard.innerHTML = `
    <h2>Gate Fallen</h2>
    <p>The outpost broke on wave ${state.wave}. You earned ${state.kills} kills and held ${state.skills.length} skills.</p>
    <div class="overlay-actions">
      <button class="btn primary" id="retry">Try again</button>
    </div>
  `;
  overlay.classList.remove("hidden");
  document.getElementById("retry").onclick = () => resetRun();
}

function endWin() {
  state.phase = "won";
  ui.start.disabled = true;
  overlayCard.innerHTML = `
    <h2>Map Cleared</h2>
    <p>All ${MAX_WAVES} waves broken. Lives left: ${state.lives}. Gold: ${Math.floor(state.gold)}. Skills: ${state.skills.length}.</p>
    <div class="overlay-actions">
      <button class="btn primary" id="again">Play again</button>
    </div>
  `;
  overlay.classList.remove("hidden");
  document.getElementById("again").onclick = () => resetRun();
}

function offerSkillPick() {
  state.phase = "pick";
  const owned = new Set(state.skills);
  const pool = SKILL_POOL.filter((s) => !owned.has(s.id));
  const picks = shuffle(pool).slice(0, 3);
  if (!picks.length) {
    state.phase = "build";
    ui.start.disabled = false;
    ui.start.textContent = state.wave >= MAX_WAVES ? "Map cleared" : "Start wave";
    if (state.wave >= MAX_WAVES) endWin();
    return;
  }
  overlayCard.innerHTML = `
    <h2>Choose a blessing</h2>
    <p>Wave ${state.wave} cleared. Pick one skill — it lasts for the rest of the run.</p>
    <div class="choice-grid">
      ${picks
        .map(
          (s, i) => `
        <button class="choice" data-i="${i}">
          <img class="icon" src="${s.icon}" alt="" />
          <span class="title">${s.name}</span>
          <span class="body">${s.body}</span>
        </button>`
        )
        .join("")}
    </div>
  `;
  overlay.classList.remove("hidden");
  overlayCard.querySelectorAll(".choice").forEach((btn) => {
    btn.onclick = () => {
      const sk = picks[Number(btn.dataset.i)];
      state.skills.push(sk.id);
      sk.apply(state.mods);
      // Fortify / war chest mutate mods.lives/gold as side channel
      if (state.mods.lives) {
        state.lives += state.mods.lives;
        state.mods.lives = 0;
      }
      if (state.mods.gold) {
        state.gold += state.mods.gold;
        state.mods.gold = 0;
      }
      hideOverlay();
      refreshSkills();
      syncHud();
      refreshSelection();
      if (state.wave >= MAX_WAVES) {
        endWin();
      } else {
        state.phase = "build";
        ui.start.disabled = false;
        ui.start.textContent = "Start wave";
      }
    };
  });
}

function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function spawnParticles(x, y, color, n) {
  for (let i = 0; i < n; i++) {
    const ang = Math.random() * Math.PI * 2;
    const spd = 20 + Math.random() * 70;
    state.particles.push({
      x,
      y,
      vx: Math.cos(ang) * spd,
      vy: Math.sin(ang) * spd,
      life: 0.35 + Math.random() * 0.35,
      color,
      size: 2 + Math.random() * 2.5,
    });
  }
}

function update(dt) {
  if (state.phase === "won" || state.phase === "lost" || state.phase === "pick") return;
  state.time += dt;
  if (state.shake > 0) state.shake = Math.max(0, state.shake - dt);

  if (state.phase === "combat") {
    const wave = WAVES[state.wave - 1];
    if (state.spawnQueue.length) {
      state.spawnTimer -= dt;
      if (state.spawnTimer <= 0) {
        spawnEnemy(state.spawnQueue.shift());
        state.spawnTimer = wave.delay;
      }
    }

    for (const e of state.enemies) {
      if (e.slowTimer > 0) {
        e.slowTimer -= dt;
        if (e.slowTimer <= 0) e.slow = 0;
      }
      const spd = e.speed * (1 - Math.min(0.75, e.slow));
      const pathLen = pathPoints.length - 1;
      // progress units: 1 tile ≈ TILE px; convert speed px/s into path index units
      e.progress += (spd * dt) / TILE;
      const p = enemyPos(e);
      e.x = p.x;
      e.y = p.y;
      if (e.progress >= pathLen) {
        e.hp = 0;
        e.leaked = true;
      }
    }

    for (const tower of state.towers) {
      tower.cooldown -= dt;
      if (tower.cooldown > 0) continue;
      const { range, rate } = towerStats(tower);
      const targets = findTargets(tower, range * TILE, 1 + state.mods.extraTargets);
      if (!targets.length) continue;
      fireTower(tower, targets);
      tower.cooldown = rate;
    }

    for (const proj of state.projectiles) {
      const target = state.enemies.find((e) => e.id === proj.targetId);
      if (target) {
        const p = enemyPos(target);
        proj.tx = p.x;
        proj.ty = p.y;
      }
      const dx = proj.tx - proj.x;
      const dy = proj.ty - proj.y;
      const d = Math.hypot(dx, dy) || 1;
      const step = proj.speed * dt;
      if (d <= step) {
        proj.x = proj.tx;
        proj.y = proj.ty;
        proj.hit = true;
        if (target && target.hp > 0) applyHit(proj, target);
      } else {
        proj.x += (dx / d) * step;
        proj.y += (dy / d) * step;
      }
      proj.life -= dt;
    }
    state.projectiles = state.projectiles.filter((p) => !p.hit && p.life > 0);

    const survivors = [];
    for (const e of state.enemies) {
      if (e.leaked) {
        leakEnemy(e);
        continue;
      }
      if (e.hp <= 0) {
        killEnemy(e);
        continue;
      }
      survivors.push(e);
    }
    state.enemies = survivors;

    if (
      state.phase === "combat" &&
      !state.spawnQueue.length &&
      !state.enemies.length &&
      !state.projectiles.length
    ) {
      syncHud();
      offerSkillPick();
    }
  }

  for (const p of state.particles) {
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vy += 40 * dt;
    p.life -= dt;
  }
  state.particles = state.particles.filter((p) => p.life > 0);

  syncHud();
  refreshSelection();
}

function draw() {
  const shakeX = state.shake ? (Math.random() - 0.5) * 8 * state.shake : 0;
  const shakeY = state.shake ? (Math.random() - 0.5) * 8 * state.shake : 0;
  ctx.save();
  ctx.translate(shakeX, shakeY);

  // Ground
  const g = ctx.createLinearGradient(0, 0, 0, canvas.height);
  g.addColorStop(0, "#243528");
  g.addColorStop(1, "#1a241c");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // Subtle grid / grass noise
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const shade = ((c * 17 + r * 31) % 5) / 5;
      ctx.fillStyle = `rgba(80, 120, 60, ${0.04 + shade * 0.05})`;
      ctx.fillRect(c * TILE, r * TILE, TILE, TILE);
    }
  }

  // Path
  ctx.strokeStyle = "#6b5638";
  ctx.lineWidth = TILE * 0.72;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.beginPath();
  pathPoints.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
  ctx.stroke();
  ctx.strokeStyle = "#8a7350";
  ctx.lineWidth = TILE * 0.48;
  ctx.beginPath();
  pathPoints.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
  ctx.stroke();

  // Gate
  const gate = pathPoints.at(-1);
  ctx.fillStyle = "#3a2a1c";
  ctx.fillRect(gate.x - 18, gate.y - 22, 36, 44);
  ctx.strokeStyle = "#d4a84b";
  ctx.lineWidth = 2;
  ctx.strokeRect(gate.x - 18, gate.y - 22, 36, 44);
  ctx.fillStyle = "#d4a84b";
  ctx.font = "600 11px IBM Plex Sans";
  ctx.textAlign = "center";
  ctx.fillText("GATE", gate.x, gate.y - 28);

  // Spawn marker
  const spawn = pathPoints[0];
  ctx.fillStyle = "rgba(196, 71, 58, 0.35)";
  ctx.beginPath();
  ctx.arc(spawn.x, spawn.y, 14, 0, Math.PI * 2);
  ctx.fill();

  // Build hover
  if (state.hoverTile && state.selectedBuild) {
    const { c, r } = state.hoverTile;
    const ok = buildable.has(key(c, r)) && !state.towers.some((t) => t.c === c && t.r === r);
    ctx.fillStyle = ok ? "rgba(127, 188, 90, 0.28)" : "rgba(196, 71, 58, 0.28)";
    ctx.fillRect(c * TILE + 2, r * TILE + 2, TILE - 4, TILE - 4);
    if (ok) {
      const def = TOWER_DEFS[state.selectedBuild];
      const range = def.range * state.mods.rangeMul * TILE;
      const p = tileCenter(c, r);
      ctx.strokeStyle = "rgba(212, 168, 75, 0.35)";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(p.x, p.y, range, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  // Towers
  for (const tower of state.towers) {
    const { def, range } = towerStats(tower);
    if (tower === state.selectedTower) {
      ctx.strokeStyle = "rgba(212, 168, 75, 0.45)";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(tower.x, tower.y, range * TILE, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.fillStyle = "#1a2218";
    ctx.beginPath();
    ctx.arc(tower.x, tower.y, 14, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = def.color;
    ctx.lineWidth = 3;
    ctx.stroke();
    const icon = images[def.icon];
    if (icon) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(icon, tower.x - 14, tower.y - 14, 28, 28);
    } else {
      ctx.fillStyle = def.color;
      ctx.fillRect(tower.x - 8, tower.y - 8, 16, 16);
    }
    // Level pips
    for (let i = 0; i < tower.level; i++) {
      ctx.fillStyle = "#d4a84b";
      ctx.fillRect(tower.x - 10 + i * 8, tower.y + 16, 6, 3);
    }
  }

  // Enemies
  for (const e of state.enemies) {
    const def = ENEMY_DEFS[e.type];
    const img = images[def.sprite];
    const size = 28 * def.scale;
    ctx.save();
    if (e.slow > 0) {
      ctx.shadowColor = "#5a9bb8";
      ctx.shadowBlur = 8;
    }
    if (img) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(img, e.x - size / 2, e.y - size / 2, size, size);
    } else {
      ctx.fillStyle = "#9ad06c";
      ctx.beginPath();
      ctx.arc(e.x, e.y, 10, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
    // HP bar
    const pct = Math.max(0, e.hp / e.maxHp);
    ctx.fillStyle = "#1a1a1a";
    ctx.fillRect(e.x - 14, e.y - size / 2 - 8, 28, 4);
    ctx.fillStyle = pct > 0.35 ? "#7cbc5a" : "#c4473a";
    ctx.fillRect(e.x - 14, e.y - size / 2 - 8, 28 * pct, 4);
  }

  // Projectiles
  for (const p of state.projectiles) {
    ctx.fillStyle = p.color;
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.kind === "fire" ? 5 : 3.5, 0, Math.PI * 2);
    ctx.fill();
    if (p.kind === "fire") {
      ctx.fillStyle = "rgba(255, 180, 80, 0.35)";
      ctx.beginPath();
      ctx.arc(p.x, p.y, 9, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // Particles
  for (const p of state.particles) {
    ctx.globalAlpha = Math.max(0, p.life * 2);
    ctx.fillStyle = p.color;
    ctx.fillRect(p.x, p.y, p.size, p.size);
    ctx.globalAlpha = 1;
  }

  // Combat banner
  if (state.phase === "combat") {
    ctx.fillStyle = "rgba(0,0,0,0.35)";
    ctx.fillRect(canvas.width / 2 - 70, 10, 140, 26);
    ctx.fillStyle = "#e8dfc4";
    ctx.font = "600 13px IBM Plex Sans";
    ctx.textAlign = "center";
    ctx.fillText(`Wave ${state.wave}`, canvas.width / 2, 28);
  }

  ctx.restore();
}

function canvasTileFromEvent(ev) {
  const rect = canvas.getBoundingClientRect();
  const x = ((ev.clientX - rect.left) / rect.width) * canvas.width;
  const y = ((ev.clientY - rect.top) / rect.height) * canvas.height;
  const c = Math.floor(x / TILE);
  const r = Math.floor(y / TILE);
  if (c < 0 || r < 0 || c >= COLS || r >= ROWS) return null;
  return { c, r, x, y };
}

function bindUi() {
  canvas.addEventListener("mousemove", (ev) => {
    state.hoverTile = canvasTileFromEvent(ev);
  });
  canvas.addEventListener("mouseleave", () => {
    state.hoverTile = null;
  });
  canvas.addEventListener("click", (ev) => {
    const tile = canvasTileFromEvent(ev);
    if (!tile) return;
    placeTower(tile.c, tile.r);
  });

  ui.upgrade.onclick = upgradeSelected;
  ui.sell.onclick = sellSelected;
  ui.start.onclick = startWave;
  ui.speed.onclick = () => {
    state.speed = state.speed === 1 ? 2 : state.speed === 2 ? 3 : 1;
    ui.speed.textContent = `Speed ×${state.speed}`;
  };
  ui.restart.onclick = () => resetRun();

  window.addEventListener("keydown", (ev) => {
    if (!overlay.classList.contains("hidden") && state.phase === "build" && !state.towers.length) {
      if (ev.key === "Enter" || ev.key === "Escape" || ev.key === " ") {
        ev.preventDefault();
        hideOverlay();
        return;
      }
    }
    if (ev.key === "u" || ev.key === "U") upgradeSelected();
    if (ev.key === "1") {
      state.selectedBuild = "archer";
      refreshTowerButtons();
    }
    if (ev.key === "2") {
      state.selectedBuild = "mage";
      refreshTowerButtons();
    }
    if (ev.key === "3") {
      state.selectedBuild = "frost";
      refreshTowerButtons();
    }
    if (ev.key === " " && state.phase === "build") {
      ev.preventDefault();
      startWave();
    }
  });
}

let last = performance.now();
function frame(now) {
  const raw = Math.min(0.05, (now - last) / 1000);
  last = now;
  update(raw * state.speed);
  draw();
  requestAnimationFrame(frame);
}

async function runBotDemo() {
  hideOverlay();
  // Strong early setup along the choke points
  const spots = [
    [1, 5, "archer"],
    [1, 7, "archer"],
    [2, 5, "frost"],
    [4, 3, "mage"],
  ];
  for (const [c, r, type] of spots) {
    state.selectedBuild = type;
    placeTower(c, r);
  }
  await sleep(600);
  startWave();
  state.speed = 2;
  ui.speed.textContent = "Speed ×2";
  // Drive a few waves with automatic skill picks
  for (let w = 0; w < 3; w++) {
    await waitUntil(() => state.phase === "pick" || state.phase === "lost" || state.phase === "won");
    if (state.phase !== "pick") break;
    const btn = overlayCard.querySelector(".choice");
    if (btn) btn.click();
    await sleep(400);
    if (state.phase === "build" && state.wave < MAX_WAVES) {
      // Upgrade first tower if possible
      state.selectedTower = state.towers[0] || null;
      upgradeSelected();
      await sleep(300);
      startWave();
    }
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function waitUntil(pred, timeout = 60000) {
  return new Promise((resolve, reject) => {
    const t0 = performance.now();
    const tick = () => {
      if (pred()) return resolve();
      if (performance.now() - t0 > timeout) return reject(new Error("wait timeout"));
      requestAnimationFrame(tick);
    };
    tick();
  });
}

async function main() {
  buildPathGeometry();
  await loadImages();
  bindUi();
  refreshTowerButtons();
  refreshSkills();
  refreshSelection();
  syncHud();
  const params = new URLSearchParams(location.search);
  if (params.has("bot")) {
    showIntro();
    hideOverlay();
    requestAnimationFrame(frame);
    runBotDemo().catch((err) => console.warn(err));
  } else {
    showIntro();
    requestAnimationFrame(frame);
  }
}

main();
