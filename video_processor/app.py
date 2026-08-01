# app.py - 多色块版
import os
import cv2
import base64
import tempfile
import numpy as np
from io import BytesIO
from pathlib import Path
from PIL import Image, ImageColor, ImageFilter
from flask import Flask, render_template, request, jsonify, send_file
from flask_cors import CORS
from rembg import remove, new_session
import logging
import time
from concurrent.futures import ThreadPoolExecutor
import threading
import zipfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024

processing_status = {
    'is_processing': False,
    'progress': 0,
    'total_frames': 0,
    'processed_frames': 0,
    'frames': [],
    'video_path': None,
    'fps': 8,
    'color_blocks': [],  # [{'color': '#C7BBBB', 'tolerance': 35}, ...]
    'use_ai': True
}

executor = ThreadPoolExecutor(max_workers=2)


class MultiColorBackgroundRemover:
    """多色块背景去除器 - 支持任意数量的背景色块"""

    def __init__(self, color_blocks, use_ai=True, blur_radius=3):
        """
        color_blocks: [{'color': '#C7BBBB', 'tolerance': 35}, ...]
        """
        self.color_blocks = []
        for block in color_blocks:
            try:
                rgb = ImageColor.getrgb(block['color'])
                tol = int(block.get('tolerance', 35))
                self.color_blocks.append({
                    'rgb': np.array(rgb),
                    'tolerance': tol / 100.0  # 归一化
                })
            except Exception as e:
                logger.warning(f"跳过无效颜色块 {block}: {e}")

        if not self.color_blocks:
            # 默认灰色
            self.color_blocks = [{'rgb': np.array([199, 187, 187]), 'tolerance': 0.35}]

        self.blur_radius = blur_radius
        self.use_ai = use_ai
        self.session = None

        if self.use_ai:
            logger.info("🚀 正在加载 u2net 模型...")
            try:
                self.session = new_session('u2net')
                logger.info("✅ u2net 模型加载成功！")
            except Exception as e:
                logger.error(f"❌ u2net 模型加载失败: {e}")
                try:
                    self.session = new_session('u2netp')
                    logger.info("✅ u2netp 模型加载成功！")
                except Exception as e2:
                    logger.error(f"❌ 所有模型加载失败: {e2}")
                    self.session = None
        else:
            logger.info("💡 使用纯色检测模式（不加载AI模型）")

    def detect_multi_color_background(self, image):
        """检测多个颜色块作为背景"""
        if image.mode == 'RGBA':
            rgb_image = Image.new('RGB', image.size, (255, 255, 255))
            rgb_image.paste(image, mask=image.split()[3])
            img_array = np.array(rgb_image)
        else:
            img_array = np.array(image)

        # 初始化背景掩码为False
        background_mask = np.zeros((img_array.shape[0], img_array.shape[1]), dtype=bool)

        for block in self.color_blocks:
            target = block['rgb']
            tolerance = block['tolerance']

            # 计算欧几里得距离
            distance = np.sqrt(np.sum((img_array[:, :, :3] - target) ** 2, axis=2))
            max_distance = np.sqrt(3 * 255 ** 2)
            normalized_distance = distance / max_distance

            # 阈值判断
            block_mask = normalized_distance <= tolerance
            background_mask = background_mask | block_mask

        return background_mask

    def refine_mask(self, mask):
        """优化掩码"""
        mask_image = Image.fromarray(mask.astype(np.uint8) * 255)
        mask_image = mask_image.filter(ImageFilter.MedianFilter(size=3))
        if self.blur_radius > 0:
            mask_image = mask_image.filter(ImageFilter.GaussianBlur(radius=self.blur_radius))
        return np.array(mask_image) > 128

    def remove_background(self, pil_image):
        """去除背景"""
        try:
            if pil_image.mode != 'RGB':
                pil_image = pil_image.convert('RGB')

            # 多色块检测
            color_mask = self.detect_multi_color_background(pil_image)
            refined_mask = self.refine_mask(color_mask)

            rgba_image = pil_image.convert('RGBA')

            if self.use_ai and self.session:
                try:
                    ai_result = remove(pil_image, session=self.session)
                    if ai_result and ai_result.mode == 'RGBA':
                        ai_mask_array = np.array(ai_result.split()[3]) > 128
                        color_foreground = ~refined_mask
                        combined_mask = ai_mask_array & color_foreground
                        final_mask = Image.fromarray(combined_mask)
                    else:
                        foreground_mask = ~refined_mask
                        final_mask = Image.fromarray(foreground_mask)
                except Exception as e:
                    logger.warning(f"AI处理失败，回退到纯色检测: {e}")
                    foreground_mask = ~refined_mask
                    final_mask = Image.fromarray(foreground_mask)
            else:
                foreground_mask = ~refined_mask
                final_mask = Image.fromarray(foreground_mask)

            result = Image.new('RGBA', rgba_image.size, (0, 0, 0, 0))
            result.paste(rgba_image, mask=final_mask)

            return result

        except Exception as e:
            logger.error(f"去除背景失败: {e}")
            return pil_image.convert('RGBA')


def process_frame(frame, remover, target_size=(260, 260)):
    """处理单帧"""
    try:
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        pil_image = Image.fromarray(frame_rgb)

        result = remover.remove_background(pil_image)
        result = result.resize(target_size, Image.NEAREST)

        buffer = BytesIO()
        result.save(buffer, format='PNG', optimize=True)
        buffer.seek(0)
        return base64.b64encode(buffer.getvalue()).decode('utf-8')
    except Exception as e:
        logger.error(f"处理帧失败: {e}")
        return None


def process_video_task(video_path, fps, color_blocks, use_ai, callback):
    """视频处理任务"""
    global processing_status

    try:
        processing_status['is_processing'] = True
        processing_status['progress'] = 0
        processing_status['frames'] = []

        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            callback({'error': '无法打开视频文件'})
            return

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        original_fps = cap.get(cv2.CAP_PROP_FPS)

        interval = max(1, int(original_fps / fps))

        remover = MultiColorBackgroundRemover(color_blocks, use_ai=use_ai)

        processing_status['total_frames'] = total_frames // interval
        processed = 0
        frames_data = []

        for i in range(0, total_frames, interval):
            cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            ret, frame = cap.read()

            if ret:
                img_base64 = process_frame(frame, remover)
                if img_base64:
                    frames_data.append(img_base64)

                processed += 1
                processing_status['processed_frames'] = processed
                processing_status['progress'] = int((processed / max(1, processing_status['total_frames'])) * 100)

                callback({
                    'progress': processing_status['progress'],
                    'processed': processed,
                    'total': processing_status['total_frames']
                })

        cap.release()

        processing_status['frames'] = frames_data
        processing_status['is_processing'] = False

        callback({
            'done': True,
            'total_frames': len(frames_data)
        })

    except Exception as e:
        logger.error(f"处理任务失败: {e}")
        processing_status['is_processing'] = False
        callback({'error': str(e)})


# ============ 路由 ============

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/upload', methods=['POST'])
def upload_video():
    global processing_status

    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中，请稍候...'}), 400

    if 'video' not in request.files:
        return jsonify({'error': '没有上传视频文件'}), 400

    file = request.files['video']
    if file.filename == '':
        return jsonify({'error': '未选择文件'}), 400

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
    file.save(temp_file.name)
    temp_file.close()

    processing_status['video_path'] = temp_file.name

    return jsonify({'success': True, 'message': '视频上传成功'})


@app.route('/process', methods=['POST'])
def start_processing():
    global processing_status

    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中'}), 400

    if not processing_status['video_path'] or not os.path.exists(processing_status['video_path']):
        return jsonify({'error': '请先上传视频'}), 400

    data = request.get_json() or {}
    fps = int(data.get('fps', 8))
    use_ai = data.get('use_ai', True)
    color_blocks = data.get('color_blocks', [])

    # 确保至少有一个色块
    if not color_blocks:
        color_blocks = [{'color': '#C7BBBB', 'tolerance': 35}]

    processing_status['fps'] = fps
    processing_status['color_blocks'] = color_blocks
    processing_status['use_ai'] = use_ai
    processing_status['frames'] = []

    def task():
        process_video_task(
            processing_status['video_path'],
            fps,
            color_blocks,
            use_ai,
            lambda data: None
        )

    executor.submit(task)

    return jsonify({'success': True, 'message': '开始处理'})


@app.route('/status', methods=['GET'])
def get_status():
    global processing_status
    return jsonify({
        'is_processing': processing_status['is_processing'],
        'progress': processing_status['progress'],
        'processed': processing_status['processed_frames'],
        'total': processing_status['total_frames'],
        'frame_count': len(processing_status['frames'])
    })


@app.route('/frames', methods=['GET'])
def get_frames():
    global processing_status
    start = int(request.args.get('start', 0))
    end = int(request.args.get('end', 50))
    frames = processing_status['frames'][start:start + end]
    return jsonify({'frames': frames, 'total': len(processing_status['frames'])})


@app.route('/export', methods=['POST'])
def export_frames():
    global processing_status

    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中，请稍候...'}), 400

    frames = processing_status['frames']
    if not frames:
        return jsonify({'error': '没有可导出的帧，请先处理视频'}), 400

    data = request.get_json() or {}
    prefix = data.get('prefix', 'frame_')

    output_dir = Path('output_frames')
    if output_dir.exists():
        import shutil
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    exported_count = 0
    for i, frame_base64 in enumerate(frames):
        try:
            img_data = base64.b64decode(frame_base64)
            img = Image.open(BytesIO(img_data))
            filename = f"{prefix}{i + 1}.png"
            filepath = output_dir / filename
            img.save(filepath, 'PNG')
            exported_count += 1
        except Exception as e:
            logger.error(f"导出帧 {i} 失败: {e}")

    return jsonify({
        'success': True,
        'exported': exported_count,
        'total': len(frames),
        'directory': str(output_dir.absolute())
    })


@app.route('/export/zip', methods=['POST'])
def export_frames_zip():
    global processing_status

    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中，请稍候...'}), 400

    frames = processing_status['frames']
    if not frames:
        return jsonify({'error': '没有可导出的帧，请先处理视频'}), 400

    data = request.get_json() or {}
    prefix = data.get('prefix', 'frame_')

    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    temp_zip.close()

    try:
        with zipfile.ZipFile(temp_zip.name, 'w', zipfile.ZIP_DEFLATED) as zf:
            for i, frame_base64 in enumerate(frames):
                try:
                    img_data = base64.b64decode(frame_base64)
                    filename = f"{prefix}{i + 1}.png"
                    zf.writestr(filename, img_data)
                except Exception as e:
                    logger.error(f"添加帧 {i} 到ZIP失败: {e}")

        return send_file(
            temp_zip.name,
            as_attachment=True,
            download_name=f"frames_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip",
            mimetype='application/zip'
        )
    except Exception as e:
        logger.error(f"创建ZIP失败: {e}")
        return jsonify({'error': f'导出失败: {str(e)}'}), 500
    finally:
        try:
            os.unlink(temp_zip.name)
        except:
            pass


@app.route('/clear', methods=['POST'])
def clear_data():
    global processing_status
    processing_status['frames'] = []
    processing_status['progress'] = 0
    processing_status['processed_frames'] = 0
    processing_status['total_frames'] = 0

    if processing_status['video_path'] and os.path.exists(processing_status['video_path']):
        try:
            os.unlink(processing_status['video_path'])
        except:
            pass
        processing_status['video_path'] = None

    return jsonify({'success': True})


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000, threaded=True)