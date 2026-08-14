"""
rooms.json 可视化编辑器
启动方式: python app.py
然后在浏览器打开 http://localhost:8765
"""
import copy
import json
import os
from flask import Flask, jsonify, request, send_file, render_template_string

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOMS_JSON = os.path.join(BASE_DIR, "rooms.json")
LOOT_TABLES_JSON = os.path.join(os.path.join(BASE_DIR, "..", "inventory"), "loot_tables.json")
ITEMS_JSON = os.path.join(os.path.join(BASE_DIR, "..", "inventory"), "items.json")
ASSETS_DIR = os.path.join(os.path.join(BASE_DIR, ".."), "assets")

# loot_tables.json 被删除后，编辑器以此表作为新文件初始内容。
# capacity / generation 属于箱子类型；star_levels 分别配置 1~3 星区域的逐格刷新规则。
DEFAULT_LOOT_TABLES = {
    "chest_types": {
        "hospital_medicine": {
            "capacity": 18,
            "generation": "per_slot_probability",
            "star_levels": {
                "1": {"rules": [
                    {"chance": 0.20, "item": "魔素结晶_1", "min_count": 1, "max_count": 3},
                    {"chance": 0.08, "item": "魔素结晶_2", "min_count": 1, "max_count": 1},
                ]},
                "2": {"rules": [
                    {"chance": 0.28, "item": "魔素结晶_1", "min_count": 2, "max_count": 4},
                    {"chance": 0.14, "item": "魔素结晶_2", "min_count": 1, "max_count": 2},
                ]},
                "3": {"rules": [
                    {"chance": 0.34, "item": "魔素结晶_1", "min_count": 2, "max_count": 5},
                    {"chance": 0.22, "item": "魔素结晶_2", "min_count": 1, "max_count": 3},
                ]},
            },
        },
        "office_supply": {
            "capacity": 24,
            "generation": "per_slot_probability",
            "star_levels": {
                "1": {"rules": [
                    {"chance": 0.28, "item": "电子元件_1", "min_count": 1, "max_count": 4},
                    {"chance": 0.12, "item": "电子元件_2", "min_count": 1, "max_count": 2},
                    {"chance": 0.18, "item": "钢材_1", "min_count": 1, "max_count": 3},
                    {"chance": 0.07, "item": "魔素结晶_1", "min_count": 1, "max_count": 2},
                ]},
                "2": {"rules": [
                    {"chance": 0.30, "item": "电子元件_1", "min_count": 2, "max_count": 5},
                    {"chance": 0.18, "item": "电子元件_2", "min_count": 1, "max_count": 3},
                    {"chance": 0.20, "item": "钢材_1", "min_count": 2, "max_count": 4},
                    {"chance": 0.10, "item": "魔素结晶_1", "min_count": 1, "max_count": 3},
                ]},
                "3": {"rules": [
                    {"chance": 0.30, "item": "电子元件_1", "min_count": 3, "max_count": 6},
                    {"chance": 0.24, "item": "电子元件_2", "min_count": 2, "max_count": 4},
                    {"chance": 0.22, "item": "钢材_1", "min_count": 2, "max_count": 5},
                    {"chance": 0.14, "item": "魔素结晶_1", "min_count": 2, "max_count": 4},
                ]},
            },
        },
        "warehouse": {
            "capacity": 24,
            "generation": "none",
            "star_levels": {"1": {"rules": []}, "2": {"rules": []}, "3": {"rules": []}},
        },
        "city1_office_茶水间_chest_0": {
            "capacity": 24,
            "generation": "per_slot_probability",
            "star_levels": {
                "1": {"rules": [
                    {"chance": 0.10, "item": "电子元件_1", "min_count": 1, "max_count": 1},
                    {"chance": 0.10, "item": "钢材_1", "min_count": 1, "max_count": 1},
                ]},
                "2": {"rules": [
                    {"chance": 0.16, "item": "电子元件_1", "min_count": 1, "max_count": 2},
                    {"chance": 0.14, "item": "钢材_1", "min_count": 1, "max_count": 2},
                ]},
                "3": {"rules": [
                    {"chance": 0.22, "item": "电子元件_1", "min_count": 2, "max_count": 3},
                    {"chance": 0.18, "item": "钢材_1", "min_count": 2, "max_count": 3},
                    {"chance": 0.08, "item": "电子元件_2", "min_count": 1, "max_count": 1},
                ]},
            },
        },
        "city1_office_茶水间_chest_1": {
            "capacity": 24,
            "generation": "per_slot_probability",
            "star_levels": {
                "1": {"rules": [{"chance": 0.10, "item": "魔素结晶_1", "min_count": 1, "max_count": 1}]},
                "2": {"rules": [{"chance": 0.18, "item": "魔素结晶_1", "min_count": 1, "max_count": 2}]},
                "3": {"rules": [
                    {"chance": 0.22, "item": "魔素结晶_1", "min_count": 2, "max_count": 3},
                    {"chance": 0.08, "item": "魔素结晶_2", "min_count": 1, "max_count": 1},
                ]},
            },
        },
    }
}


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_loot_tables():
    if not os.path.exists(LOOT_TABLES_JSON):
        return copy.deepcopy(DEFAULT_LOOT_TABLES)
    data = load_json(LOOT_TABLES_JSON)
    chest_types = data.get("chest_types", {}) if isinstance(data, dict) else {}
    # 旧版顶层 rules 不再参与编辑；返回新默认表，保存时即可重建文件。
    if any("star_levels" not in entry for entry in chest_types.values() if isinstance(entry, dict)):
        return copy.deepcopy(DEFAULT_LOOT_TABLES)
    return data


@app.route("/")
def index():
    return render_template_string(HTML_TEMPLATE)


@app.route("/api/rooms")
def get_rooms():
    return jsonify(load_json(ROOMS_JSON))


@app.route("/api/rooms/save", methods=["POST"])
def save_rooms():
    data = request.get_json()
    save_json(ROOMS_JSON, data)
    return jsonify({"ok": True})


@app.route("/api/chest_types")
def get_chest_types():
    data = load_loot_tables()
    return jsonify(list(data.get("chest_types", {}).keys()))


@app.route("/api/texture")
def serve_texture():
    city = request.args.get("city", "city1")
    building = request.args.get("building", "office")
    room_id = request.args.get("room_id", "")
    path = os.path.join(ASSETS_DIR, city, building, f"{room_id}.png")
    if os.path.exists(path):
        return send_file(path, mimetype="image/png")
    return ("", 404)


@app.route("/api/loot_tables")
def get_loot_tables():
    return jsonify(load_loot_tables())


@app.route("/api/loot_tables/save", methods=["POST"])
def save_loot_tables():
    data = request.get_json()
    if not isinstance(data, dict) or not isinstance(data.get("chest_types"), dict):
        return jsonify({"ok": False, "error": "chest_types 必须是对象"}), 400
    save_json(LOOT_TABLES_JSON, data)
    return jsonify({"ok": True})


@app.route("/api/items")
def get_items():
    data = load_json(ITEMS_JSON)
    return jsonify(list(data.get("items", {}).keys()))


HTML_TEMPLATE = r"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>Rooms.json 可视化编辑器</title>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family: 'Microsoft YaHei', sans-serif; background:#1a1a2e; color:#eee; display:flex; height:100vh; overflow:hidden; }
#sidebar { width:280px; background:#16213e; padding:16px; overflow-y:auto; flex-shrink:0; }
#main { flex:1; display:flex; flex-direction:column; }
#toolbar { background:#0f3460; padding:8px 16px; display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
#canvas-wrap { flex:1; overflow:auto; background:#0a0a1a; display:flex; align-items:center; justify-content:center; position:relative; }
canvas { cursor:crosshair; image-rendering:pixelated; }
#props { margin-top:12px; }
h3 { color:#e94560; margin-bottom:8px; font-size:14px; }
select, input, button, textarea { background:#1a1a3e; color:#eee; border:1px solid #333; padding:6px 8px; border-radius:4px; font-size:13px; width:100%; }
select { cursor:pointer; }
button { cursor:pointer; background:#e94560; border-color:#e94560; font-weight:bold; margin-top:4px; }
button:hover { background:#ff6b81; }
button.danger { background:#c0392b; border-color:#c0392b; }
button.danger:hover { background:#e74c3c; }
button.secondary { background:#0f3460; border-color:#0f3460; }
button.secondary:hover { background:#1a4a7a; }
.form-group { margin-bottom:8px; }
.form-group label { display:block; font-size:12px; color:#aaa; margin-bottom:2px; }
.row { display:flex; gap:8px; }
.row > * { flex:1; }
.point-list { max-height:200px; overflow-y:auto; margin-top:4px; }
.point-item { background:#1a1a3e; padding:4px 8px; margin:3px 0; border-radius:4px; font-size:12px; display:flex; justify-content:space-between; align-items:center; cursor:pointer; }
.point-item:hover { background:#2a2a5e; }
.point-item.active { background:#e94560; }
.point-item .del { color:#e94560; cursor:pointer; font-weight:bold; padding:0 4px; }
.point-item .del:hover { color:#ff6b81; }
.info { font-size:11px; color:#666; margin-top:8px; }
#coords { font-size:12px; color:#888; padding:4px 8px; }
#save-status { font-size:12px; color:#4caf50; margin-left:8px; }
.legend { display:flex; gap:12px; margin:8px 0; font-size:12px; }
.legend span { display:flex; align-items:center; gap:4px; }
.legend .dot { width:12px; height:12px; border-radius:50%; display:inline-block; }
.loot-section { margin-top:12px; border-top:1px solid #333; padding-top:8px; }
.loot-rule { background:#1a1a3e; padding:6px 8px; margin:4px 0; border-radius:4px; font-size:12px; }
.loot-rule .row { margin-bottom:4px; }
.loot-rule .row:last-child { margin-bottom:0; }
.loot-rule input { width:100%; padding:3px 4px; font-size:11px; }
.loot-rule label { font-size:10px; color:#888; }
.loot-rule-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:4px; }
.loot-rule-header span { font-size:11px; color:#aaa; }
.loot-rule-header .del-rule { color:#e94560; cursor:pointer; font-size:14px; }
.loot-rule-header .del-rule:hover { color:#ff6b81; }
.btn-sm { padding:3px 8px; font-size:11px; margin-top:2px; }
</style>
</head>
<body>

<div id="sidebar">
  <h3>导航</h3>
  <div class="form-group">
    <label>城市</label>
    <select id="sel-city"></select>
  </div>
  <div class="form-group">
    <label>建筑</label>
    <select id="sel-building"></select>
  </div>
  <div class="form-group">
    <label>房间</label>
    <select id="sel-room"></select>
  </div>

  <div id="props" style="display:none;">
    <h3>房间属性</h3>
    <div class="form-group">
      <label>楼层数</label>
      <input type="number" id="prop-floor-count" min="1" max="20">
    </div>
    <div class="form-group">
      <label>传送门位置 X</label>
      <input type="number" id="prop-portal-x" step="any">
    </div>
    <div class="form-group">
      <label>传送门位置 Y</label>
      <input type="number" id="prop-portal-y" step="any">
    </div>

    <h3 style="margin-top:12px;">点位列表</h3>
    <div class="legend">
      <span><span class="dot" style="background:#4fc3f7;"></span>调查点</span>
      <span><span class="dot" style="background:#ffd54f;"></span>箱子</span>
    </div>
    <div class="point-list" id="point-list"></div>
    <div class="row">
      <button onclick="addPoint('investigation')">+ 调查点</button>
      <button onclick="addPoint('chest')">+ 箱子</button>
    </div>
    <button class="secondary" onclick="deleteSelected()">删除选中点位</button>

    <div id="point-props" style="display:none; margin-top:12px;">
      <h3 id="point-props-title">点位属性</h3>
      <div id="point-props-fields"></div>
      <button onclick="updatePointFromForm()">应用修改</button>
    </div>

    <div id="loot-editor" style="display:none;" class="loot-section">
      <h3>战利品表编辑</h3>
      <div class="form-group">
        <label>战利品类型 ID</label>
        <input id="loot-type-id" readonly style="color:#888;">
      </div>
      <div class="form-group">
        <label>capacity (容量)</label>
        <input type="number" id="loot-capacity" min="1" value="24">
      </div>
      <div class="form-group">
        <label>generation (生成模式)</label>
        <select id="loot-generation">
          <option value="per_slot_probability">per_slot_probability</option>
          <option value="none">none</option>
        </select>
      </div>
      <div class="form-group">
        <label>区域星级</label>
        <select id="loot-star-level" onchange="switchLootStarLevel()">
          <option value="1">※ 1 星</option>
          <option value="2">※※ 2 星</option>
          <option value="3">※※※ 3 星</option>
        </select>
      </div>
      <div id="loot-rules"></div>
      <button class="btn-sm" onclick="addLootRule()">+ 添加规则</button>
      <button class="secondary btn-sm" style="margin-top:8px;" onclick="saveLootTables()">保存战利品表</button>
      <span id="loot-save-status"></span>
    </div>

    <button style="margin-top:16px;" onclick="saveRooms()">保存到 JSON</button>
    <span id="save-status"></span>
    <div class="info">点击画布添加点位 · 拖拽移动 · 点击列表选中编辑</div>
  </div>
</div>

<div id="main">
  <div id="toolbar">
    <span id="coords">坐标: -</span>
    <label style="font-size:12px;">房间宽度: <input type="number" id="room-width-input" value="938" step="1" style="width:80px;display:inline;"></label>
    <button class="secondary" style="width:auto;" onclick="refreshCanvas()">刷新画布</button>
  </div>
  <div id="canvas-wrap">
    <canvas id="canvas"></canvas>
  </div>
</div>

<script>
let roomsData = {};
let lootTablesData = {};
let itemsList = [];
let chestTypes = [];
let selectedPointIndex = -1;
let selectedLootStarLevel = '1';
let isDragging = false;
let dragPointIndex = -1;
let bgImage = null;
let imageLoaded = false;
let imgNaturalW = 0;
let imgNaturalH = 0;

const COLORS = {
  investigation: '#4fc3f7',
  investigation_border: '#0288d1',
  chest: '#ffd54f',
  chest_border: '#f57f17',
};

const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');

// ======== DATA LOADING ========

async function loadData() {
  const [roomsRes, chestRes, lootRes, itemsRes] = await Promise.all([
    fetch('/api/rooms'),
    fetch('/api/chest_types'),
    fetch('/api/loot_tables'),
    fetch('/api/items'),
  ]);
  roomsData = await roomsRes.json();
  chestTypes = await chestRes.json();
  lootTablesData = await lootRes.json();
  itemsList = await itemsRes.json();
  populateSelectors();
}

function populateSelectors() {
  const citySel = document.getElementById('sel-city');
  citySel.innerHTML = '';
  for (const city of Object.keys(roomsData)) {
    const opt = document.createElement('option');
    opt.value = city;
    opt.textContent = city;
    citySel.appendChild(opt);
  }
  onCityChange();
}

function onCityChange() {
  const city = document.getElementById('sel-city').value;
  const bSel = document.getElementById('sel-building');
  bSel.innerHTML = '';
  const buildings = roomsData[city] || {};
  for (const b of Object.keys(buildings)) {
    const opt = document.createElement('option');
    opt.value = b;
    opt.textContent = b;
    bSel.appendChild(opt);
  }
  onBuildingChange();
}

function onBuildingChange() {
  const city = document.getElementById('sel-city').value;
  const building = document.getElementById('sel-building').value;
  const rSel = document.getElementById('sel-room');
  rSel.innerHTML = '';
  const bData = (roomsData[city] || {})[building] || {};
  const rooms = bData.rooms || [];
  for (const room of rooms) {
    const opt = document.createElement('option');
    opt.value = room.id;
    opt.textContent = room.id;
    rSel.appendChild(opt);
  }
  onRoomChange();
}

function onRoomChange() {
  updateBuildingProps();
  loadTexture();
  updatePointList();
}

// ======== BUILDING PROPERTIES ========

function getBuildingData() {
  const city = document.getElementById('sel-city').value;
  const building = document.getElementById('sel-building').value;
  return (roomsData[city] || {})[building] || {};
}

function getRoomData() {
  const bData = getBuildingData();
  const roomId = document.getElementById('sel-room').value;
  return (bData.rooms || []).find(r => r.id === roomId) || {};
}

function updateBuildingProps() {
  const bData = getBuildingData();
  document.getElementById('props').style.display = 'block';
  document.getElementById('prop-floor-count').value = bData.floor_count || 5;
  const pp = bData.portal_positions || [0, 0];
  document.getElementById('prop-portal-x').value = pp[0] || 0;
  document.getElementById('prop-portal-y').value = pp[1] || 0;
}

function applyBuildingProps() {
  const bData = getBuildingData();
  bData.floor_count = parseInt(document.getElementById('prop-floor-count').value) || 5;
  bData.portal_positions = [
    parseFloat(document.getElementById('prop-portal-x').value) || 0,
    parseFloat(document.getElementById('prop-portal-y').value) || 0,
  ];
}

// ======== TEXTURE LOADING ========

function loadTexture() {
  imageLoaded = false;
  bgImage = null;
  const city = document.getElementById('sel-city').value;
  const building = document.getElementById('sel-building').value;
  const roomId = document.getElementById('sel-room').value;
  const img = new Image();
  img.onload = function() {
    bgImage = img;
    imgNaturalW = img.naturalWidth;
    imgNaturalH = img.naturalHeight;
    imageLoaded = true;
    document.getElementById('room-width-input').value = imgNaturalW;
    refreshCanvas();
  };
  img.onerror = function() {
    imageLoaded = false;
    bgImage = null;
    refreshCanvas();
  };
  img.src = `/api/texture?city=${encodeURIComponent(city)}&building=${encodeURIComponent(building)}&room_id=${encodeURIComponent(roomId)}`;
}

// ======== COORDINATE MAPPING ========

// Content coords -> canvas pixel coords
function contentToPixel(cx, cy) {
  const roomWidth = parseFloat(document.getElementById('room-width-input').value) || imgNaturalW;
  const px = cx - roomWidth / 2 + imgNaturalW / 2;
  const py = cy + 225 + imgNaturalH / 2;
  return [px, py];
}

// Canvas pixel coords -> content coords
function pixelToContent(px, py) {
  const roomWidth = parseFloat(document.getElementById('room-width-input').value) || imgNaturalW;
  const cx = px - imgNaturalW / 2 + roomWidth / 2;
  const cy = py - 225 - imgNaturalH / 2;
  return [Math.round(cx * 100) / 100, Math.round(cy * 100) / 100];
}

// ======== CANVAS RENDERING ========

function refreshCanvas() {
  if (!imageLoaded) {
    canvas.width = 400;
    canvas.height = 300;
    ctx.fillStyle = '#1a1a2e';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#666';
    ctx.font = '14px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('无贴图', canvas.width / 2, canvas.height / 2);
    return;
  }
  canvas.width = imgNaturalW;
  canvas.height = imgNaturalH;
  drawCanvas();
}

function drawCanvas() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  if (bgImage) {
    ctx.drawImage(bgImage, 0, 0);
  }

  const roomData = getRoomData();

  // Draw investigation points
  (roomData.investigation_points || []).forEach((pt, i) => {
    const [px, py] = contentToPixel(pt.position[0], pt.position[1]);
    drawPoint(px, py, 'investigation', i);
  });

  // Draw chests
  (roomData.chests || []).forEach((ch, i) => {
    const [px, py] = contentToPixel(ch.position[0], ch.position[1]);
    drawPoint(px, py, 'chest', i);
  });
}

function drawPoint(px, py, type, index) {
  const color = COLORS[type];
  const borderColor = COLORS[type + '_border'];
  const isSelected = (type === 'investigation' && selectedPointIndex === index && getSelectedType() === 'investigation')
                  || (type === 'chest' && selectedPointIndex === index && getSelectedType() === 'chest');

  ctx.beginPath();
  ctx.arc(px, py, isSelected ? 10 : 7, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.strokeStyle = borderColor;
  ctx.lineWidth = 2;
  ctx.stroke();

  // Label
  ctx.fillStyle = '#000';
  ctx.font = 'bold 10px sans-serif';
  ctx.textAlign = 'center';
  const label = type === 'investigation' ? '调' : '箱';
  ctx.fillText(label, px, py + 3);
}

// ======== MOUSE INTERACTION ========

function getMousePos(e) {
  const rect = canvas.getBoundingClientRect();
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;
  return [
    (e.clientX - rect.left) * scaleX,
    (e.clientY - rect.top) * scaleY,
  ];
}

function findPointAt(mx, my) {
  const roomData = getRoomData();
  const threshold = 12;
  // Check investigation points
  const ips = roomData.investigation_points || [];
  for (let i = 0; i < ips.length; i++) {
    const [px, py] = contentToPixel(ips[i].position[0], ips[i].position[1]);
    if (Math.hypot(mx - px, my - py) < threshold) return { type: 'investigation', index: i };
  }
  // Check chests
  const chests = roomData.chests || [];
  for (let i = 0; i < chests.length; i++) {
    const [px, py] = contentToPixel(chests[i].position[0], chests[i].position[1]);
    if (Math.hypot(mx - px, my - py) < threshold) return { type: 'chest', index: i };
  }
  return null;
}

canvas.addEventListener('mousedown', (e) => {
  const [mx, my] = getMousePos(e);
  const hit = findPointAt(mx, my);
  if (hit) {
    dragPointIndex = hit.index;
    isDragging = true;
    selectPoint(hit.type, hit.index);
  } else {
    selectedPointIndex = -1;
    updatePointList();
    updatePointProperties();
    updateLootEditor();
    drawCanvas();
  }
});

canvas.addEventListener('mousemove', (e) => {
  const [mx, my] = getMousePos(e);
  const [cx, cy] = pixelToContent(mx, my);
  document.getElementById('coords').textContent = `坐标: (${cx.toFixed(1)}, ${cy.toFixed(1)})`;

  if (isDragging && dragPointIndex >= 0) {
    const roomData = getRoomData();
    const selType = getSelectedType();
    if (selType === 'investigation') {
      const ips = roomData.investigation_points || [];
      if (dragPointIndex < ips.length) {
        ips[dragPointIndex].position = [cx, cy];
      }
    } else if (selType === 'chest') {
      const chests = roomData.chests || [];
      if (dragPointIndex < chests.length) {
        chests[dragPointIndex].position = [cx, cy];
      }
    }
    drawCanvas();
    updatePointList();
  }
});

canvas.addEventListener('mouseup', () => {
  isDragging = false;
  dragPointIndex = -1;
});

canvas.addEventListener('mouseleave', () => {
  isDragging = false;
  dragPointIndex = -1;
});

canvas.addEventListener('dblclick', (e) => {
  const [mx, my] = getMousePos(e);
  const hit = findPointAt(mx, my);
  if (!hit && imageLoaded) {
    showAddPointDialog(mx, my);
  }
});

// ======== POINT MANAGEMENT ========

function getSelectedType() {
  // Track it separately
  return selectedPointType || 'investigation';
}
let selectedPointType = 'investigation';

function showAddPointDialog(mx, my) {
  const [cx, cy] = pixelToContent(mx, my);
  const type = confirm('选择点位类型:\n"确定" = 调查点\n"取消" = 箱子') ? 'investigation' : 'chest';
  addPointAt(type, cx, cy);
}

function addPoint(type) {
  // Add at center of texture
  const cx = 0;
  const cy = -225;
  addPointAt(type, cx, cy);
}

function addPointAt(type, cx, cy) {
  const roomData = getRoomData();
  if (type === 'investigation') {
    if (!roomData.investigation_points) roomData.investigation_points = [];
    const city = document.getElementById('sel-city').value;
    const building = document.getElementById('sel-building').value;
    const roomId = document.getElementById('sel-room').value;
    roomData.investigation_points.push({
      position: [cx, cy],
      investigation_id: `${city}_${building}_${roomId}_inv_${roomData.investigation_points.length}`,
      message: '调查点描述',
      investigation_name: '调查',
    });
    selectedPointIndex = roomData.investigation_points.length - 1;
    selectedPointType = 'investigation';
  } else if (type === 'chest') {
    if (!roomData.chests) roomData.chests = [];
    const city = document.getElementById('sel-city').value;
    const building = document.getElementById('sel-building').value;
    const roomId = document.getElementById('sel-room').value;
    roomData.chests.push({
      position: [cx, cy],
      type: `${city}_${building}_${roomId}_chest_${roomData.chests.length}`,
      name: '箱子',
    });
    selectedPointIndex = roomData.chests.length - 1;
    selectedPointType = 'chest';
  }
  drawCanvas();
  updatePointList();
  updatePointProperties();
}

function selectPoint(type, index) {
  collectLootRules();
  selectedPointType = type;
  selectedPointIndex = index;
  updatePointList();
  updatePointProperties();
  updateLootEditor();
  drawCanvas();
}

function deleteSelected() {
  if (selectedPointIndex < 0) return;
  const roomData = getRoomData();
  if (selectedPointType === 'investigation') {
    (roomData.investigation_points || []).splice(selectedPointIndex, 1);
  } else if (selectedPointType === 'chest') {
    (roomData.chests || []).splice(selectedPointIndex, 1);
  }
  selectedPointIndex = -1;
  drawCanvas();
  updatePointList();
  updatePointProperties();
  updateLootEditor();
}

// ======== POINT LIST UI ========

function updatePointList() {
  const roomData = getRoomData();
  const container = document.getElementById('point-list');
  let html = '';

  (roomData.investigation_points || []).forEach((pt, i) => {
    const cls = (selectedPointType === 'investigation' && selectedPointIndex === i) ? 'active' : '';
    html += `<div class="point-item ${cls}" onclick="selectPoint('investigation',${i})">
      <span><span style="color:#4fc3f7;">●</span> 调查点 #${i+1}: (${pt.position[0].toFixed(0)},${pt.position[1].toFixed(0)})</span>
      <span class="del" onclick="event.stopPropagation();selectPoint('investigation',${i});deleteSelected();">✕</span>
    </div>`;
  });

  (roomData.chests || []).forEach((ch, i) => {
    const cls = (selectedPointType === 'chest' && selectedPointIndex === i) ? 'active' : '';
    html += `<div class="point-item ${cls}" onclick="selectPoint('chest',${i})">
      <span><span style="color:#ffd54f;">●</span> 箱子 #${i+1}: (${ch.position[0].toFixed(0)},${ch.position[1].toFixed(0)})</span>
      <span class="del" onclick="event.stopPropagation();selectPoint('chest',${i});deleteSelected();">✕</span>
    </div>`;
  });

  container.innerHTML = html || '<div style="color:#666;font-size:12px;">暂无点位</div>';
}

// ======== POINT PROPERTIES FORM ========

function updatePointProperties() {
  const container = document.getElementById('point-props');
  const fields = document.getElementById('point-props-fields');
  const title = document.getElementById('point-props-title');

  if (selectedPointIndex < 0) {
    container.style.display = 'none';
    return;
  }

  container.style.display = 'block';
  const roomData = getRoomData();

  if (selectedPointType === 'investigation') {
    const pt = (roomData.investigation_points || [])[selectedPointIndex];
    if (!pt) { container.style.display = 'none'; return; }
    title.textContent = `调查点 #${selectedPointIndex + 1}`;
    fields.innerHTML = `
      <div class="form-group">
        <label>investigation_id</label>
        <input id="f-inv-id" value="${escapeHtml(pt.investigation_id || '')}">
      </div>
      <div class="form-group">
        <label>investigation_name (显示名称)</label>
        <input id="f-inv-name" value="${escapeHtml(pt.investigation_name || '')}">
      </div>
      <div class="form-group">
        <label>message (调查文本)</label>
        <textarea id="f-inv-msg" rows="3">${escapeHtml(pt.message || '')}</textarea>
      </div>
      <div class="row">
        <div class="form-group">
          <label>position X</label>
          <input type="number" id="f-inv-px" value="${pt.position[0]}" step="any">
        </div>
        <div class="form-group">
          <label>position Y</label>
          <input type="number" id="f-inv-py" value="${pt.position[1]}" step="any">
        </div>
      </div>
    `;
  } else if (selectedPointType === 'chest') {
    const ch = (roomData.chests || [])[selectedPointIndex];
    if (!ch) { container.style.display = 'none'; return; }
    title.textContent = `箱子 #${selectedPointIndex + 1}`;
    fields.innerHTML = `
      <div class="form-group">
        <label>type (战利品类型)</label>
        <input id="f-chest-type" value="${escapeHtml(ch.type || '')}" list="chest-type-suggestions">
        <datalist id="chest-type-suggestions">${chestTypes.map(t => `<option value="${t}">`).join('')}</datalist>
      </div>
      <div class="form-group">
        <label>name (显示名称)</label>
        <input id="f-chest-name" value="${escapeHtml(ch.name || '')}">
      </div>
      <div class="row">
        <div class="form-group">
          <label>position X</label>
          <input type="number" id="f-chest-px" value="${ch.position[0]}" step="any">
        </div>
        <div class="form-group">
          <label>position Y</label>
          <input type="number" id="f-chest-py" value="${ch.position[1]}" step="any">
        </div>
      </div>
    `;
  }
}

function updatePointFromForm() {
  if (selectedPointIndex < 0) return;
  const roomData = getRoomData();

  if (selectedPointType === 'investigation') {
    const pt = (roomData.investigation_points || [])[selectedPointIndex];
    if (!pt) return;
    pt.investigation_id = document.getElementById('f-inv-id').value;
    pt.investigation_name = document.getElementById('f-inv-name').value;
    pt.message = document.getElementById('f-inv-msg').value;
    pt.position = [
      parseFloat(document.getElementById('f-inv-px').value) || 0,
      parseFloat(document.getElementById('f-inv-py').value) || 0,
    ];
  } else if (selectedPointType === 'chest') {
    const ch = (roomData.chests || [])[selectedPointIndex];
    if (!ch) return;
    ch.type = document.getElementById('f-chest-type').value;
    ch.name = document.getElementById('f-chest-name').value;
    ch.position = [
      parseFloat(document.getElementById('f-chest-px').value) || 0,
      parseFloat(document.getElementById('f-chest-py').value) || 0,
    ];
  }

  drawCanvas();
  updatePointList();
  updateLootEditor();
}

function escapeHtml(s) {
  return (s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ======== LOOT TABLE EDITOR ========

function ensureLootEntry(chestType) {
  if (!lootTablesData.chest_types || typeof lootTablesData.chest_types !== 'object') {
    lootTablesData.chest_types = {};
  }
  if (!lootTablesData.chest_types[chestType]) {
    lootTablesData.chest_types[chestType] = {
      capacity: 24,
      generation: 'per_slot_probability',
      star_levels: {},
    };
  }
  const entry = lootTablesData.chest_types[chestType];
  if (!entry.star_levels || typeof entry.star_levels !== 'object') entry.star_levels = {};
  for (const level of ['1', '2', '3']) {
    if (!entry.star_levels[level] || typeof entry.star_levels[level] !== 'object') {
      entry.star_levels[level] = { rules: [] };
    }
    if (!Array.isArray(entry.star_levels[level].rules)) entry.star_levels[level].rules = [];
  }
  return entry;
}

function updateLootEditor() {
  const container = document.getElementById('loot-editor');
  if (selectedPointIndex < 0 || selectedPointType !== 'chest') {
    container.style.display = 'none';
    return;
  }
  container.style.display = 'block';

  const roomData = getRoomData();
  const ch = (roomData.chests || [])[selectedPointIndex];
  if (!ch) { container.style.display = 'none'; return; }

  const chestType = ch.type || '';
  document.getElementById('loot-type-id').value = chestType;

  const existing = ensureLootEntry(chestType);
  selectedLootStarLevel = '1';
  document.getElementById('loot-star-level').value = selectedLootStarLevel;
  document.getElementById('loot-capacity').value = existing.capacity || 24;
  document.getElementById('loot-generation').value = existing.generation || 'per_slot_probability';

  renderLootRules(existing.star_levels[selectedLootStarLevel].rules);
}

function switchLootStarLevel() {
  collectLootRules();
  selectedLootStarLevel = document.getElementById('loot-star-level').value;
  const chestType = document.getElementById('loot-type-id').value;
  if (!chestType) return;
  const entry = ensureLootEntry(chestType);
  renderLootRules(entry.star_levels[selectedLootStarLevel].rules);
}

function renderLootRules(rules) {
  const container = document.getElementById('loot-rules');
  let html = '';
  rules.forEach((rule, i) => {
    html += `
    <div class="loot-rule">
      <div class="loot-rule-header">
        <span>规则 #${i + 1}</span>
        <span class="del-rule" onclick="deleteLootRule(${i})">✕</span>
      </div>
      <div class="row">
        <div class="form-group">
          <label>chance</label>
          <input type="number" id="lr-chance-${i}" value="${rule.chance}" step="any" min="0" max="1">
        </div>
        <div class="form-group">
          <label>item</label>
          <input id="lr-item-${i}" value="${escapeHtml(rule.item || '')}" list="items-suggestions">
        </div>
      </div>
      <div class="row">
        <div class="form-group">
          <label>min_count</label>
          <input type="number" id="lr-min-${i}" value="${rule.min_count || 1}" min="1">
        </div>
        <div class="form-group">
          <label>max_count</label>
          <input type="number" id="lr-max-${i}" value="${rule.max_count || 1}" min="1">
        </div>
      </div>
    </div>`;
  });
  html += `<datalist id="items-suggestions">${itemsList.map(t => `<option value="${t}">`).join('')}</datalist>`;
  container.innerHTML = html || '<div style="color:#666;font-size:12px;">暂无规则</div>';
}

function addLootRule() {
  const chestType = document.getElementById('loot-type-id').value;
  if (!chestType) return;
  collectLootRules();
  const entry = ensureLootEntry(chestType);
  const rules = entry.star_levels[selectedLootStarLevel].rules;
  rules.push({ chance: 0.1, item: itemsList[0] || '', min_count: 1, max_count: 1 });
  renderLootRules(rules);
}

function deleteLootRule(index) {
  const chestType = document.getElementById('loot-type-id').value;
  if (!chestType) return;
  collectLootRules();
  const entry = ensureLootEntry(chestType);
  const rules = entry.star_levels[selectedLootStarLevel].rules;
  rules.splice(index, 1);
  renderLootRules(rules);
}

function collectLootRules() {
  const chestType = document.getElementById('loot-type-id').value;
  if (!chestType) return;
  const entry = ensureLootEntry(chestType);
  entry.capacity = parseInt(document.getElementById('loot-capacity').value) || 24;
  entry.generation = document.getElementById('loot-generation').value;
  const rules = entry.star_levels[selectedLootStarLevel].rules;
  for (let i = 0; i < rules.length; i++) {
    rules[i].chance = parseFloat(document.getElementById(`lr-chance-${i}`).value) || 0;
    rules[i].item = document.getElementById(`lr-item-${i}`).value;
    rules[i].min_count = parseInt(document.getElementById(`lr-min-${i}`).value) || 1;
    rules[i].max_count = parseInt(document.getElementById(`lr-max-${i}`).value) || 1;
  }
}

async function saveLootTables() {
  collectLootRules();
  for (const chestType of Object.keys(lootTablesData.chest_types || {})) ensureLootEntry(chestType);
  const status = document.getElementById('loot-save-status');
  try {
    const res = await fetch('/api/loot_tables/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(lootTablesData),
    });
    const result = await res.json();
    if (!res.ok) throw new Error(result.error || `HTTP ${res.status}`);
    if (result.ok) {
      status.textContent = '战利品表已保存!';
      status.style.color = '#4caf50';
      // Refresh chest types list
      const cr = await fetch('/api/chest_types');
      chestTypes = await cr.json();
      setTimeout(() => { status.textContent = ''; }, 2000);
    }
  } catch (err) {
    status.textContent = '保存失败: ' + err.message;
    status.style.color = '#e94560';
  }
}

// ======== SAVE ========

async function saveRooms() {
  applyBuildingProps();
  const status = document.getElementById('save-status');
  try {
    const res = await fetch('/api/rooms/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(roomsData),
    });
    const result = await res.json();
    if (result.ok) {
      status.textContent = '已保存!';
      status.style.color = '#4caf50';
      setTimeout(() => { status.textContent = ''; }, 2000);
    }
  } catch (err) {
    status.textContent = '保存失败: ' + err.message;
    status.style.color = '#e94560';
  }
}

// ======== EVENT BINDINGS ========

document.getElementById('sel-city').addEventListener('change', onCityChange);
document.getElementById('sel-building').addEventListener('change', onBuildingChange);
document.getElementById('sel-room').addEventListener('change', onRoomChange);

document.getElementById('prop-floor-count').addEventListener('change', () => {});
document.getElementById('prop-portal-x').addEventListener('change', () => {});
document.getElementById('prop-portal-y').addEventListener('change', () => {});

document.getElementById('room-width-input').addEventListener('change', () => {
  refreshCanvas();
  updatePointList();
});

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
  if (e.key === 'Delete' && selectedPointIndex >= 0) {
    deleteSelected();
  }
  if (e.ctrlKey && e.key === 's') {
    e.preventDefault();
    saveRooms();
  }
});

// ======== INIT ========
loadData();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    print("Rooms.json 可视化编辑器启动: http://localhost:8765")
    app.run(host="0.0.0.0", port=8765, debug=True)
