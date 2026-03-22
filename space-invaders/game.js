'use strict';

// ─── Canvas Setup ────────────────────────────────────────────────────────────
const canvas = document.getElementById('game');
const ctx    = canvas.getContext('2d');

const BASE_W = 600;
const BASE_H = 750;
let scale    = 1;

function resize() {
  const maxH = window.innerHeight - 60;
  const maxW = window.innerWidth  - 20;
  scale = Math.min(maxW / BASE_W, maxH / BASE_H, 2);
  canvas.width  = BASE_W * scale;
  canvas.height = BASE_H * scale;
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
}
resize();
window.addEventListener('resize', resize);

// ─── Constants ───────────────────────────────────────────────────────────────
const W = BASE_W;
const H = BASE_H;

const ROWS       = 4;
const COLS       = 11;
const INV_W      = 36;
const INV_H      = 28;
const INV_PAD_X  = 18;
const INV_PAD_Y  = 20;
const PLAYER_SPD = 280;   // px/s
const BULLET_SPD = 520;
const BOMB_SPD   = 180;
const BARRIER_COUNT = 4;

const INVADER_EMOJIS = ['👾', '👽', '🛸', '😈'];
const INVADER_PTS    = [10, 20, 30, 40];
const MYSTERY_PTS    = [50, 100, 150, 200, 250, 300];

// ─── State ───────────────────────────────────────────────────────────────────
let state; // 'menu' | 'playing' | 'paused' | 'gameover' | 'victory'
let score, lives, level;
let invaders, bullets, bombs, barriers, particles;
let player;
let mysteryShip;
let invaderDir, invaderBaseInterval, invaderTimer;
let bombTimer, bombInterval;
let mysteryTimer, mysteryInterval;
let fireCooldown, fireTimer;
let canFire;
let lastTime;
let stars;
let flashTimer; // player hit flash

// ─── Input ───────────────────────────────────────────────────────────────────
const keys = {};
document.addEventListener('keydown', e => {
  keys[e.code] = true;
  if (e.code === 'Space') e.preventDefault();
  if (e.code === 'KeyP' && state === 'playing') pauseGame();
  else if (e.code === 'KeyP' && state === 'paused') resumeGame();
  if (e.code === 'Enter' || e.code === 'NumpadEnter') handleEnter();
});
document.addEventListener('keyup', e => { keys[e.code] = false; });

function handleEnter() {
  if (state === 'menu')     startGame();
  else if (state === 'gameover') startGame();
  else if (state === 'victory')  nextLevel();
  else if (state === 'paused')   resumeGame();
}

// ─── Stars ───────────────────────────────────────────────────────────────────
function makeStars() {
  stars = [];
  for (let i = 0; i < 100; i++) {
    stars.push({
      x: Math.random() * W,
      y: Math.random() * H,
      r: Math.random() * 1.4 + 0.4,
      bright: Math.random(),
      speed: Math.random() * 1.2 + 0.4,
    });
  }
}

function drawStars() {
  for (const s of stars) {
    const alpha = 0.3 + 0.7 * s.bright;
    ctx.fillStyle = `rgba(255,255,255,${alpha})`;
    ctx.beginPath();
    ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
    ctx.fill();
  }
}

function updateStars(dt) {
  for (const s of stars) {
    s.bright += s.speed * dt * 0.8;
    if (s.bright > 1) { s.bright = 0; }
  }
}

// ─── Barriers ────────────────────────────────────────────────────────────────
const BLOCK_W = 8, BLOCK_H = 8;
const BARRIER_TEMPLATE = [
  [0,0,1,1,1,1,1,1,0,0],
  [0,1,1,1,1,1,1,1,1,0],
  [1,1,1,1,1,1,1,1,1,1],
  [1,1,1,1,1,1,1,1,1,1],
  [1,1,1,0,0,0,0,1,1,1],
  [1,1,0,0,0,0,0,0,1,1],
];

function makeBarriers() {
  barriers = [];
  const totalW = BARRIER_TEMPLATE[0].length * BLOCK_W;
  const gap = (W - BARRIER_COUNT * totalW) / (BARRIER_COUNT + 1);
  for (let b = 0; b < BARRIER_COUNT; b++) {
    const bx = gap + b * (totalW + gap);
    const by = H - 160;
    for (let r = 0; r < BARRIER_TEMPLATE.length; r++) {
      for (let c = 0; c < BARRIER_TEMPLATE[r].length; c++) {
        if (BARRIER_TEMPLATE[r][c]) {
          barriers.push({ x: bx + c * BLOCK_W, y: by + r * BLOCK_H, w: BLOCK_W, h: BLOCK_H });
        }
      }
    }
  }
}

// ─── Invaders ────────────────────────────────────────────────────────────────
function makeInvaders() {
  invaders = [];
  const startX = (W - (COLS * (INV_W + INV_PAD_X) - INV_PAD_X)) / 2 + INV_W / 2;
  const startY = 110;
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      invaders.push({
        x: startX + c * (INV_W + INV_PAD_X),
        y: startY + r * (INV_H + INV_PAD_Y),
        row: r,
        alive: true,
        frame: Math.random() * Math.PI * 2, // animation phase
      });
    }
  }
}

function aliveInvaders() {
  return invaders.filter(inv => inv.alive);
}

// ─── Game Init ───────────────────────────────────────────────────────────────
function initGame() {
  score    = 0;
  lives    = 3;
  level    = 1;
  bullets  = [];
  bombs    = [];
  particles = [];
  flashTimer = 0;
  mysteryShip = null;

  player = { x: W / 2, y: H - 70, w: 44, h: 28, alive: true };

  makeStars();
  makeBarriers();
  makeInvaders();
  resetInvaderTiming();

  bombInterval    = 2.0;
  bombTimer       = bombInterval;
  mysteryInterval = 18;
  mysteryTimer    = mysteryInterval * 0.5;
  fireCooldown    = 0.32;
  fireTimer       = 0;
  canFire         = true;
  invaderDir      = 1;
  lastTime        = null;
}

function resetInvaderTiming() {
  invaderBaseInterval = Math.max(0.12, 0.65 - (level - 1) * 0.07);
  invaderTimer        = invaderBaseInterval;
}

function startGame() {
  initGame();
  state = 'playing';
  requestAnimationFrame(loop);
}

function pauseGame()  { state = 'paused'; }
function resumeGame() { state = 'playing'; lastTime = null; requestAnimationFrame(loop); }

// ─── Shooting ────────────────────────────────────────────────────────────────
function fireBullet() {
  if (!canFire) return;
  canFire   = false;
  fireTimer = 0;
  bullets.push({ x: player.x, y: player.y - player.h / 2 - 4, w: 3, h: 12, vy: -BULLET_SPD });
  spawnMuzzleFlash(player.x, player.y - player.h / 2);
}

function dropBomb() {
  const alive = aliveInvaders();
  if (!alive.length) return;
  const inv = alive[Math.floor(Math.random() * alive.length)];
  bombs.push({ x: inv.x, y: inv.y + INV_H / 2 + 4, w: 4, h: 10, vy: BOMB_SPD + level * 15 });
}

function spawnMysteryShip() {
  if (mysteryShip && mysteryShip.alive) return;
  mysteryShip = { x: -30, y: 68, w: 50, h: 22, alive: true, vx: 110 + level * 10 };
}

// ─── Particles ───────────────────────────────────────────────────────────────
function spawnExplosion(x, y, color1, color2, count = 10) {
  for (let i = 0; i < count; i++) {
    const angle = (Math.PI * 2 * i) / count + Math.random() * 0.4;
    const spd   = 40 + Math.random() * 80;
    particles.push({
      x, y,
      vx: Math.cos(angle) * spd,
      vy: Math.sin(angle) * spd,
      r: 2 + Math.random() * 4,
      life: 0.5 + Math.random() * 0.4,
      maxLife: 0.9,
      color: Math.random() > 0.5 ? color1 : color2,
    });
  }
}

function spawnScorePopup(x, y, pts) {
  particles.push({
    x, y, vx: 0, vy: -40,
    r: 0, life: 0.9, maxLife: 0.9,
    text: `+${pts}`, color: pts >= 100 ? '#ff0' : '#fff',
    isText: true,
  });
}

function spawnMuzzleFlash(x, y) {
  for (let i = 0; i < 6; i++) {
    const angle = -Math.PI / 2 + (Math.random() - 0.5) * 1.2;
    particles.push({
      x, y,
      vx: Math.cos(angle) * (30 + Math.random() * 40),
      vy: Math.sin(angle) * (30 + Math.random() * 40),
      r: 1 + Math.random() * 3,
      life: 0.12, maxLife: 0.12,
      color: '#ff8',
    });
  }
}

// ─── Collision Helper ─────────────────────────────────────────────────────────
function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh) {
  return ax - aw/2 < bx + bw/2 &&
         ax + aw/2 > bx - bw/2 &&
         ay - ah/2 < by + bh/2 &&
         ay + ah/2 > by - bh/2;
}

// ─── Update ───────────────────────────────────────────────────────────────────
function update(dt) {
  updateStars(dt);

  if (state !== 'playing') return;

  // Player movement
  if ((keys['ArrowLeft'] || keys['KeyA']) && player.x - player.w / 2 > 10) {
    player.x -= PLAYER_SPD * dt;
  }
  if ((keys['ArrowRight'] || keys['KeyD']) && player.x + player.w / 2 < W - 10) {
    player.x += PLAYER_SPD * dt;
  }

  // Fire
  if (!canFire) {
    fireTimer += dt;
    if (fireTimer >= fireCooldown) canFire = true;
  }
  if ((keys['Space'] || keys['KeyZ']) && canFire) fireBullet();

  // Flash timer
  if (flashTimer > 0) flashTimer -= dt;

  // Bullets
  for (let i = bullets.length - 1; i >= 0; i--) {
    const b = bullets[i];
    b.y += b.vy * dt;
    if (b.y < -20) { bullets.splice(i, 1); continue; }

    // vs invaders
    let hitInv = false;
    for (const inv of invaders) {
      if (!inv.alive) continue;
      if (rectsOverlap(b.x, b.y, b.w, b.h, inv.x, inv.y, INV_W, INV_H)) {
        inv.alive = false;
        const pts = INVADER_PTS[inv.row];
        score += pts;
        spawnExplosion(inv.x, inv.y, '#f80', '#ff0');
        spawnScorePopup(inv.x, inv.y - 10, pts);
        bullets.splice(i, 1);
        hitInv = true;
        break;
      }
    }
    if (hitInv) continue;

    // vs mystery ship
    if (mysteryShip && mysteryShip.alive) {
      if (rectsOverlap(b.x, b.y, b.w, b.h, mysteryShip.x, mysteryShip.y, mysteryShip.w, mysteryShip.h)) {
        mysteryShip.alive = false;
        const pts = MYSTERY_PTS[Math.floor(Math.random() * MYSTERY_PTS.length)];
        score += pts;
        spawnExplosion(mysteryShip.x, mysteryShip.y, '#f00', '#f80', 14);
        spawnScorePopup(mysteryShip.x, mysteryShip.y - 14, pts);
        bullets.splice(i, 1);
        continue;
      }
    }

    // vs barriers
    for (let j = barriers.length - 1; j >= 0; j--) {
      const bar = barriers[j];
      if (rectsOverlap(b.x, b.y, b.w, b.h, bar.x + bar.w/2, bar.y + bar.h/2, bar.w, bar.h)) {
        barriers.splice(j, 1);
        bullets.splice(i, 1);
        break;
      }
    }
  }

  // Bombs
  for (let i = bombs.length - 1; i >= 0; i--) {
    const bm = bombs[i];
    bm.y += bm.vy * dt;
    if (bm.y > H + 20) { bombs.splice(i, 1); continue; }

    // vs player
    if (rectsOverlap(bm.x, bm.y, bm.w, bm.h, player.x, player.y, player.w, player.h)) {
      bombs.splice(i, 1);
      lives--;
      flashTimer = 1.0;
      spawnExplosion(player.x, player.y, '#f00', '#f80');
      if (lives <= 0) { state = 'gameover'; return; }
      continue;
    }

    // vs barriers
    for (let j = barriers.length - 1; j >= 0; j--) {
      const bar = barriers[j];
      if (rectsOverlap(bm.x, bm.y, bm.w, bm.h, bar.x + bar.w/2, bar.y + bar.h/2, bar.w, bar.h)) {
        // Destroy a small cluster
        const cx = bar.x, cy = bar.y;
        barriers = barriers.filter(bl => !(Math.abs(bl.x - cx) <= BLOCK_W * 1.5 && Math.abs(bl.y - cy) <= BLOCK_H * 1.5));
        bombs.splice(i, 1);
        break;
      }
    }
  }

  // Invader movement
  invaderTimer -= dt;
  if (invaderTimer <= 0) {
    const alive = aliveInvaders();
    if (!alive.length) { state = 'victory'; return; }

    // Scale speed by remaining count
    const ratio = alive.length / (ROWS * COLS);
    invaderTimer = invaderBaseInterval * Math.max(0.18, ratio);

    let hitEdge = false;
    const step = 12;
    for (const inv of alive) {
      const nx = inv.x + invaderDir * step;
      if (nx < INV_W / 2 + 12 || nx > W - INV_W / 2 - 12) { hitEdge = true; break; }
    }

    if (hitEdge) {
      invaderDir *= -1;
      for (const inv of alive) inv.y += 18;
      // Check if invaders reached the player's row
      for (const inv of alive) {
        if (inv.y + INV_H / 2 >= player.y - player.h / 2) { state = 'gameover'; return; }
      }
    } else {
      for (const inv of alive) inv.x += invaderDir * step;
    }
  }

  // Invader animation
  for (const inv of invaders) {
    inv.frame += dt * 3;
  }

  // Bombs dropping
  bombTimer -= dt;
  const curBombInterval = Math.max(0.5, bombInterval - (level - 1) * 0.12);
  if (bombTimer <= 0) {
    bombTimer = curBombInterval;
    dropBomb();
    if (level >= 3) dropBomb(); // extra bombs on higher levels
  }

  // Mystery ship
  mysteryTimer -= dt;
  if (mysteryTimer <= 0) {
    mysteryTimer = mysteryInterval;
    spawnMysteryShip();
  }
  if (mysteryShip && mysteryShip.alive) {
    mysteryShip.x += mysteryShip.vx * dt;
    if (mysteryShip.x > W + 40) mysteryShip.alive = false;
  }

  // Particles
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.x    += p.vx * dt;
    p.y    += p.vy * dt;
    p.life -= dt;
    if (p.life <= 0) particles.splice(i, 1);
  }

  // Check victory
  if (aliveInvaders().length === 0) { state = 'victory'; }
}

// ─── Draw ─────────────────────────────────────────────────────────────────────
function draw() {
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, W, H);

  drawStars();

  if (state === 'menu')     { drawMenu();     return; }
  if (state === 'gameover') { drawGameOver(); return; }

  drawBarriers();
  drawInvaders();
  if (mysteryShip && mysteryShip.alive) drawMystery();
  if (flashTimer <= 0 || Math.floor(flashTimer * 10) % 2 === 0) drawPlayer();
  drawBullets();
  drawBombs();
  drawParticles();
  drawHUD();
  drawGroundLine();

  if (state === 'paused')  drawPause();
  if (state === 'victory') drawVictory();
}

function drawPlayer() {
  const { x, y, w, h } = player;
  ctx.save();
  ctx.translate(x, y);
  ctx.fillStyle = '#0f0';
  ctx.strokeStyle = '#0a0';
  ctx.lineWidth = 1;
  // Body
  ctx.beginPath();
  ctx.moveTo(0, -h / 2);
  ctx.lineTo(-w / 2, h / 2);
  ctx.lineTo(-10, h / 2);
  ctx.lineTo(-10, h / 2 - 8);
  ctx.lineTo(10, h / 2 - 8);
  ctx.lineTo(10, h / 2);
  ctx.lineTo(w / 2, h / 2);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  // Cockpit
  ctx.fillStyle = '#8ff';
  ctx.beginPath();
  ctx.ellipse(0, -4, 5, 8, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawInvaders() {
  ctx.font = `${INV_H}px serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (const inv of invaders) {
    if (!inv.alive) continue;
    // Subtle vertical bob
    const bob = Math.sin(inv.frame) * 2;
    ctx.save();
    ctx.translate(inv.x, inv.y + bob);
    // Subtle scale pulse
    const sc = 1 + Math.sin(inv.frame * 1.2) * 0.05;
    ctx.scale(sc, sc);
    ctx.fillText(INVADER_EMOJIS[inv.row], 0, 0);
    ctx.restore();
  }
}

function drawMystery() {
  const { x, y, w, h } = mysteryShip;
  // Draw UFO shape
  ctx.save();
  ctx.translate(x, y);
  // Saucer
  ctx.fillStyle = '#f00';
  ctx.beginPath();
  ctx.ellipse(0, 4, w / 2, h / 2 - 2, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#f55';
  ctx.beginPath();
  ctx.ellipse(0, -2, w / 3, 8, 0, 0, Math.PI * 2);
  ctx.fill();
  // Windows
  ctx.fillStyle = '#ff0';
  for (let i = -1; i <= 1; i++) {
    ctx.beginPath();
    ctx.arc(i * 10, 4, 3, 0, Math.PI * 2);
    ctx.fill();
  }
  // Glow
  ctx.globalAlpha = 0.25;
  ctx.fillStyle = '#f00';
  ctx.beginPath();
  ctx.ellipse(0, 4, w / 2 + 6, h / 2 + 4, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawBullets() {
  for (const b of bullets) {
    // Glow effect
    const grd = ctx.createLinearGradient(b.x, b.y - b.h / 2, b.x, b.y + b.h / 2);
    grd.addColorStop(0, '#fff');
    grd.addColorStop(0.4, '#ff0');
    grd.addColorStop(1, '#f80');
    ctx.fillStyle = grd;
    ctx.beginPath();
    ctx.roundRect(b.x - b.w / 2, b.y - b.h / 2, b.w, b.h, 2);
    ctx.fill();
  }
}

function drawBombs() {
  for (const bm of bombs) {
    ctx.save();
    ctx.translate(bm.x, bm.y);
    // Zigzag shape
    const seg = bm.h / 3;
    ctx.strokeStyle = '#f80';
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.moveTo(0, -bm.h / 2);
    ctx.lineTo(-3, -seg);
    ctx.lineTo(3, 0);
    ctx.lineTo(-3, seg);
    ctx.lineTo(0, bm.h / 2);
    ctx.stroke();
    ctx.restore();
  }
}

function drawBarriers() {
  for (const bar of barriers) {
    const alpha = 0.85;
    ctx.fillStyle = `rgba(0, 200, 0, ${alpha})`;
    ctx.fillRect(bar.x, bar.y, bar.w - 1, bar.h - 1);
  }
}

function drawParticles() {
  for (const p of particles) {
    const alpha = p.life / p.maxLife;
    ctx.globalAlpha = alpha;
    if (p.isText) {
      ctx.fillStyle = p.color;
      ctx.font = 'bold 14px Courier New';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(p.text, p.x, p.y);
    } else {
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
}

function drawHUD() {
  ctx.fillStyle = 'rgba(0,0,0,0.6)';
  ctx.fillRect(0, 0, W, 44);
  ctx.strokeStyle = '#0f0';
  ctx.lineWidth = 1;
  ctx.beginPath(); ctx.moveTo(0, 44); ctx.lineTo(W, 44); ctx.stroke();

  ctx.fillStyle = '#0f0';
  ctx.font = 'bold 16px Courier New';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText(`SCORE: ${score}`, 12, 22);

  ctx.textAlign = 'center';
  ctx.fillStyle = '#f55';
  const livesStr = '♥'.repeat(Math.max(0, lives));
  ctx.fillText(livesStr, W / 2, 22);

  ctx.textAlign = 'right';
  ctx.fillStyle = '#0cf';
  ctx.fillText(`LVL ${level}`, W - 12, 22);
}

function drawGroundLine() {
  ctx.strokeStyle = '#0f0';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(0, H - 40);
  ctx.lineTo(W, H - 40);
  ctx.stroke();
}

// ─── Screens ──────────────────────────────────────────────────────────────────
function drawMenu() {
  ctx.textAlign = 'center';

  // Title
  ctx.save();
  const t = Date.now() / 1000;
  const grd = ctx.createLinearGradient(W / 2 - 160, 0, W / 2 + 160, 0);
  grd.addColorStop(0, '#0f0');
  grd.addColorStop(0.5, '#0ff');
  grd.addColorStop(1, '#0f0');
  ctx.fillStyle = grd;
  ctx.font = 'bold 44px Courier New';
  ctx.textBaseline = 'middle';
  ctx.shadowColor = '#0f0';
  ctx.shadowBlur = 16 + Math.sin(t * 2) * 8;
  ctx.fillText('SPACE INVADERS', W / 2, 110);
  ctx.restore();

  // Invader showcase
  const rows = [
    { emoji: '😈', pts: 40, y: 210 },
    { emoji: '🛸', pts: 30, y: 268 },
    { emoji: '👽', pts: 20, y: 326 },
    { emoji: '👾', pts: 10, y: 384 },
  ];
  ctx.font = '32px serif';
  ctx.textBaseline = 'middle';
  for (const row of rows) {
    ctx.fillText(row.emoji, W / 2 - 80, row.y);
    ctx.font = 'bold 16px Courier New';
    ctx.fillStyle = '#fff';
    ctx.textAlign = 'left';
    ctx.fillText(`= ${row.pts} PTS`, W / 2 - 50, row.y + 1);
    ctx.font = '32px serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = '#fff';
  }

  // Mystery ship row
  ctx.fillStyle = '#f00';
  ctx.font = 'bold 16px Courier New';
  ctx.textAlign = 'center';
  ctx.fillText('🚀  =  ???  PTS', W / 2, 442);

  // Divider
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 1;
  ctx.beginPath(); ctx.moveTo(80, 468); ctx.lineTo(W - 80, 468); ctx.stroke();

  // Start prompt
  const blink = Math.floor(t * 2) % 2 === 0;
  if (blink) {
    ctx.fillStyle = '#ff0';
    ctx.font = 'bold 22px Courier New';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('PRESS ENTER / CLICK TO START', W / 2, 520);
  }

  ctx.fillStyle = '#555';
  ctx.font = '14px Courier New';
  ctx.fillText('← → Move   Space Fire   P Pause', W / 2, 570);
  ctx.fillText('© 2024 SPACE INVADERS', W / 2, H - 20);
}

function drawGameOver() {
  ctx.save();
  ctx.fillStyle = 'rgba(0,0,0,0.75)';
  ctx.fillRect(0, 0, W, H);

  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  ctx.fillStyle = '#f00';
  ctx.font = 'bold 52px Courier New';
  ctx.shadowColor = '#f00';
  ctx.shadowBlur = 20;
  ctx.fillText('GAME OVER', W / 2, H / 2 - 60);
  ctx.shadowBlur = 0;

  ctx.fillStyle = '#fff';
  ctx.font = 'bold 24px Courier New';
  ctx.fillText(`SCORE: ${score}`, W / 2, H / 2);

  ctx.fillStyle = '#ff0';
  ctx.font = 'bold 18px Courier New';
  const blink = Math.floor(Date.now() / 500) % 2 === 0;
  if (blink) ctx.fillText('PRESS ENTER TO RETRY', W / 2, H / 2 + 60);
  ctx.restore();
}

function drawPause() {
  ctx.save();
  ctx.fillStyle = 'rgba(0,0,0,0.6)';
  ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = '#fff';
  ctx.font = 'bold 36px Courier New';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('PAUSED', W / 2, H / 2);
  ctx.font = '18px Courier New';
  ctx.fillStyle = '#888';
  ctx.fillText('Press P to resume', W / 2, H / 2 + 50);
  ctx.restore();
}

function drawVictory() {
  ctx.save();
  ctx.fillStyle = 'rgba(0,0,0,0.7)';
  ctx.fillRect(0, 0, W, H);

  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  const t = Date.now() / 1000;
  const grd = ctx.createLinearGradient(W / 2 - 100, 0, W / 2 + 100, 0);
  grd.addColorStop(0, '#0f0');
  grd.addColorStop(0.5, '#ff0');
  grd.addColorStop(1, '#0f0');
  ctx.fillStyle = grd;
  ctx.font = 'bold 52px Courier New';
  ctx.shadowColor = '#0f0';
  ctx.shadowBlur = 16 + Math.sin(t * 3) * 8;
  ctx.fillText('YOU WIN!', W / 2, H / 2 - 70);
  ctx.shadowBlur = 0;

  ctx.fillStyle = '#fff';
  ctx.font = 'bold 24px Courier New';
  ctx.fillText(`SCORE: ${score}`, W / 2, H / 2 - 10);

  ctx.fillStyle = '#ff0';
  ctx.font = 'bold 20px Courier New';
  const blink = Math.floor(Date.now() / 500) % 2 === 0;
  if (blink) ctx.fillText(`PRESS ENTER — LEVEL ${level + 1}`, W / 2, H / 2 + 55);
  ctx.restore();
}

// ─── Next Level ───────────────────────────────────────────────────────────────
function nextLevel() {
  level++;
  bullets  = [];
  bombs    = [];
  particles = [];
  mysteryShip = null;

  makeBarriers();
  makeInvaders();
  resetInvaderTiming();

  bombTimer       = Math.max(0.5, bombInterval - (level - 1) * 0.12);
  mysteryTimer    = mysteryInterval * 0.6;
  invaderDir      = 1;
  state           = 'playing';
  lastTime        = null;
}

// ─── Click to Start / Restart ─────────────────────────────────────────────────
canvas.addEventListener('click', () => {
  if (state === 'menu')     startGame();
  else if (state === 'gameover') startGame();
  else if (state === 'victory')  nextLevel();
});

// ─── Main Loop ────────────────────────────────────────────────────────────────
function loop(ts) {
  if (lastTime === null) lastTime = ts;
  const dt = Math.min((ts - lastTime) / 1000, 0.05); // cap at 50ms
  lastTime = ts;

  update(dt);
  draw();

  if (state !== 'gameover') {
    requestAnimationFrame(loop);
  } else {
    // Still animate the game over screen
    requestAnimationFrame(loop);
  }
}

// ─── Boot ─────────────────────────────────────────────────────────────────────
makeStars();
state = 'menu';
requestAnimationFrame(loop);
