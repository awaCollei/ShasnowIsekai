# app.py - 完整修改版

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

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # 500MB限制

# 全局变量存储处理状态
processing_status = {
    'is_processing': False,
    'progress': 0,
    'total_frames': 0,
    'processed_frames': 0,
    'frames': [],
    'video_path': None,
    'fps': 8,
    'tolerance': 35,
    'use_ai': True  # 默认使用AI模型
}

# 线程池
executor = ThreadPoolExecutor(max_workers=2)

class GrayBackgroundRemover:
    """灰色背景去除器"""
    
    def __init__(self, target_color='#C2C2C2', tolerance=35, blur_radius=3, use_ai=True):
        self.target_color = ImageColor.getrgb(target_color)
        self.tolerance = tolerance
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
                logger.info("🔄 尝试加载 u2netp 作为备选...")
                try:
                    self.session = new_session('u2netp')
                    logger.info("✅ u2netp 模型加载成功！")
                except Exception as e2:
                    logger.error(f"❌ 所有模型加载失败: {e2}")
                    self.session = None
        else:
            logger.info("💡 使用纯色背景检测模式（不加载AI模型）")
    
    def detect_gray_background(self, image):
        """检测灰色背景"""
        if image.mode == 'RGBA':
            rgb_image = Image.new('RGB', image.size, (255, 255, 255))
            rgb_image.paste(image, mask=image.split()[3])
            img_array = np.array(rgb_image)
        else:
            img_array = np.array(image)
        
        target = np.array(self.target_color)
        distance = np.sqrt(np.sum((img_array[:, :, :3] - target) ** 2, axis=2))
        max_distance = np.sqrt(3 * 255**2)
        normalized_distance = distance / max_distance
        threshold = self.tolerance / 100
        background_mask = normalized_distance <= threshold
        
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
            
            # 颜色检测（始终执行）
            color_mask = self.detect_gray_background(pil_image)
            refined_mask = self.refine_mask(color_mask)
            
            # 转换为RGBA
            rgba_image = pil_image.convert('RGBA')
            
            if self.use_ai and self.session:
                # AI去背景
                try:
                    ai_result = remove(pil_image, session=self.session)
                    if ai_result and ai_result.mode == 'RGBA':
                        # return ai_result
                        ai_mask_array = np.array(ai_result.split()[3]) > 128
                        color_foreground = ~refined_mask
                        combined_mask = ai_mask_array & color_foreground
                        final_mask = Image.fromarray(combined_mask)
                    else:
                        # AI失败，回退到纯色检测
                        foreground_mask = ~refined_mask
                        final_mask = Image.fromarray(foreground_mask)
                except Exception as e:
                    logger.warning(f"AI处理失败，回退到纯色检测: {e}")
                    foreground_mask = ~refined_mask
                    final_mask = Image.fromarray(foreground_mask)
            else:
                # 纯色检测模式
                foreground_mask = ~refined_mask
                final_mask = Image.fromarray(foreground_mask)
            
            # 应用掩码
            result = Image.new('RGBA', rgba_image.size, (0, 0, 0, 0))
            result.paste(rgba_image, mask=final_mask)
            
            return result
            
        except Exception as e:
            logger.error(f"去除背景失败: {e}")
            return pil_image.convert('RGBA')

def process_frame(frame, remover, target_size=(260, 260)):
    """处理单帧：去背景 + 压缩"""
    try:
        # OpenCV BGR -> RGB
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        pil_image = Image.fromarray(frame_rgb)
        
        # 去背景
        result = remover.remove_background(pil_image)
        
        # 压缩到目标尺寸
        result = result.resize(target_size, Image.NEAREST)
        
        # 转换为base64
        buffer = BytesIO()
        result.save(buffer, format='PNG', optimize=True)
        buffer.seek(0)
        img_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
        
        return img_base64
    except Exception as e:
        logger.error(f"处理帧失败: {e}")
        return None

def process_video_task(video_path, fps, tolerance, use_ai, callback):
    """视频处理任务"""
    global processing_status
    
    try:
        processing_status['is_processing'] = True
        processing_status['progress'] = 0
        processing_status['frames'] = []
        
        # 打开视频
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            callback({'error': '无法打开视频文件'})
            return
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        original_fps = cap.get(cv2.CAP_PROP_FPS)
        
        # 计算采样间隔
        interval = max(1, int(original_fps / fps))
        
        # 创建去除器
        remover = GrayBackgroundRemover(tolerance=tolerance, use_ai=use_ai)
        
        processing_status['total_frames'] = total_frames // interval
        processed = 0
        frames_data = []
        
        for i in range(0, total_frames, interval):
            cap.set(cv2.CAP_PROP_POS_FRAMES, i)
            ret, frame = cap.read()
            
            if ret:
                # 处理帧
                img_base64 = process_frame(frame, remover)
                if img_base64:
                    frames_data.append(img_base64)
                
                processed += 1
                processing_status['processed_frames'] = processed
                processing_status['progress'] = int((processed / processing_status['total_frames']) * 100)
                
                # 更新进度
                callback({
                    'progress': processing_status['progress'],
                    'processed': processed,
                    'total': processing_status['total_frames']
                })
        
        cap.release()
        
        # 保存结果
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
    
    # 保存临时文件
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
    file.save(temp_file.name)
    temp_file.close()
    
    processing_status['video_path'] = temp_file.name
    
    return jsonify({
        'success': True,
        'message': '视频上传成功'
    })

@app.route('/process', methods=['POST'])
def start_processing():
    global processing_status
    
    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中'}), 400
    
    if not processing_status['video_path'] or not os.path.exists(processing_status['video_path']):
        return jsonify({'error': '请先上传视频'}), 400
    
    data = request.get_json() or {}
    fps = int(data.get('fps', 8))
    tolerance = int(data.get('tolerance', 35))
    use_ai = data.get('use_ai', True)
    
    processing_status['fps'] = fps
    processing_status['tolerance'] = tolerance
    processing_status['use_ai'] = use_ai
    
    # 启动处理线程
    def callback(data):
        pass
    
    def task():
        process_video_task(
            processing_status['video_path'],
            fps,
            tolerance,
            use_ai,
            lambda data: None
        )
    
    executor.submit(task)
    
    return jsonify({
        'success': True,
        'message': '开始处理'
    })

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
    
    return jsonify({
        'frames': frames,
        'total': len(processing_status['frames'])
    })

@app.route('/export', methods=['POST'])
def export_frames():
    """导出帧为PNG文件"""
    global processing_status
    
    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中，请稍候...'}), 400
    
    frames = processing_status['frames']
    if not frames:
        return jsonify({'error': '没有可导出的帧，请先处理视频'}), 400
    
    data = request.get_json() or {}
    prefix = data.get('prefix', 'frame_')
    
    # 创建输出目录
    output_dir = Path('output_frames')
    if output_dir.exists():
        # 清空目录
        import shutil
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 导出帧
    exported_count = 0
    for i, frame_base64 in enumerate(frames):
        try:
            # 解码base64
            img_data = base64.b64decode(frame_base64)
            img = Image.open(BytesIO(img_data))
            
            # 保存为PNG
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
    """导出帧为ZIP压缩包"""
    global processing_status
    
    if processing_status['is_processing']:
        return jsonify({'error': '正在处理中，请稍候...'}), 400
    
    frames = processing_status['frames']
    if not frames:
        return jsonify({'error': '没有可导出的帧，请先处理视频'}), 400
    
    data = request.get_json() or {}
    prefix = data.get('prefix', 'frame_')
    
    # 创建临时ZIP文件
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
        # 清理临时文件
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
    
    # 清理临时文件
    if processing_status['video_path'] and os.path.exists(processing_status['video_path']):
        try:
            os.unlink(processing_status['video_path'])
        except:
            pass
        processing_status['video_path'] = None
    
    return jsonify({'success': True})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000, threaded=True)