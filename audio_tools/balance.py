import os
import json
import tempfile
import shutil
from pathlib import Path
from flask import Flask, request, jsonify, send_file, send_from_directory
from flask_cors import CORS
import numpy as np
import soundfile as sf
import librosa
from scipy import signal

app = Flask(__name__, static_folder='.', static_url_path='')
CORS(app)

# 配置
BASE_DIR = Path(__file__).parent.parent  # 上级目录
TEMP_EXCLUDE = "temp"  # 排除的文件夹名
SUPPORTED_EXT = {'.mp3', '.wav'}


@app.route('/')
def index():
    """提供前端页面"""
    return send_from_directory('.', 'index.html')


def get_audio_files():
    """扫描上级目录及子目录中的音频文件，排除 temp/ 文件夹"""
    audio_files = []
    if not BASE_DIR.exists():
        return audio_files
    
    for root, dirs, files in os.walk(BASE_DIR):
        # 排除 temp 目录
        dirs[:] = [d for d in dirs if d != TEMP_EXCLUDE]
        
        for file in files:
            ext = Path(file).suffix.lower()
            if ext in SUPPORTED_EXT:
                full_path = Path(root) / file
                rel_path = full_path.relative_to(BASE_DIR)
                audio_files.append({
                    'path': str(full_path),
                    'name': file,
                    'size': full_path.stat().st_size,
                    'db': 0.0  # 默认增益
                })
    
    return sorted(audio_files, key=lambda x: x['name'])


@app.route('/api/scan', methods=['GET'])
def scan_files():
    """扫描音频文件"""
    try:
        files = get_audio_files()
        return jsonify({'files': files})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/waveform', methods=['POST'])
def get_waveform():
    """获取音频波形数据"""
    try:
        data = request.get_json()
        file_path = data.get('path')
        if not file_path or not os.path.exists(file_path):
            return jsonify({'error': '文件不存在'}), 404
        
        # 使用 librosa 加载音频
        y, sr = librosa.load(file_path, sr=None, mono=True)
        
        # 降采样显示（最多保留 2000 个点）
        max_points = 2000
        if len(y) > max_points:
            indices = np.linspace(0, len(y)-1, max_points, dtype=int)
            y = y[indices]
        
        # 转换为列表以便 JSON 传输
        waveform = y.tolist()
        
        return jsonify({
            'waveform': waveform,
            'sampleRate': sr,
            'duration': len(y) / sr if sr > 0 else 0
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/save', methods=['POST'])
def save_audio():
    """保存调整音量后的音频文件（直接覆盖原文件）"""
    try:
        data = request.get_json()
        file_path = data.get('path')
        gain_db = float(data.get('gainDb', 0))
        
        if not file_path or not os.path.exists(file_path):
            return jsonify({'error': '文件不存在'}), 404
        
        # 加载音频
        y, sr = librosa.load(file_path, sr=None, mono=False)
        
        # 应用增益 (dB 转线性)
        gain_linear = 10 ** (gain_db / 20)
        y_adjusted = y * gain_linear
        
        # 防止削波
        if np.max(np.abs(y_adjusted)) > 1.0:
            y_adjusted = y_adjusted / np.max(np.abs(y_adjusted)) * 0.99
        
        # 保存回原文件
        ext = Path(file_path).suffix.lower()
        if ext == '.wav':
            sf.write(file_path, y_adjusted.T if y_adjusted.ndim > 1 else y_adjusted, sr)
        elif ext == '.mp3':
            # 使用临时文件保存，然后替换（soundfile 不支持 mp3）
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
                tmp_path = tmp.name
                sf.write(tmp_path, y_adjusted.T if y_adjusted.ndim > 1 else y_adjusted, sr)
            # 使用 ffmpeg 转换（需要安装 ffmpeg）
            import subprocess
            try:
                subprocess.run([
                    'ffmpeg', '-y', '-i', tmp_path, '-acodec', 'libmp3lame',
                    '-ab', '192k', file_path
                ], capture_output=True, check=True)
            except FileNotFoundError:
                # 如果 ffmpeg 不可用，尝试用 pydub
                try:
                    from pydub import AudioSegment
                    audio = AudioSegment.from_wav(tmp_path)
                    audio.export(file_path, format='mp3', bitrate='192k')
                except ImportError:
                    os.unlink(tmp_path)
                    return jsonify({'error': '需要 ffmpeg 或 pydub 来处理 MP3 格式'}), 500
            finally:
                if os.path.exists(tmp_path):
                    os.unlink(tmp_path)
        else:
            return jsonify({'error': f'不支持的格式: {ext}'}), 400
        
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/preview', methods=['POST'])
def preview_audio():
    """生成预览音频（返回临时 WAV 文件）"""
    try:
        data = request.get_json()
        file_path = data.get('path')
        gain_db = float(data.get('gainDb', 0))
        
        if not file_path or not os.path.exists(file_path):
            return jsonify({'error': '文件不存在'}), 404
        
        # 加载音频（只加载前 5 秒用于预览）
        y, sr = librosa.load(file_path, sr=None, mono=False, duration=5)
        
        # 应用增益
        gain_linear = 10 ** (gain_db / 20)
        y_adjusted = y * gain_linear
        
        # 防止削波
        if np.max(np.abs(y_adjusted)) > 1.0:
            y_adjusted = y_adjusted / np.max(np.abs(y_adjusted)) * 0.99
        
        # 保存为临时 WAV
        tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
        tmp_path = tmp.name
        tmp.close()
        sf.write(tmp_path, y_adjusted.T if y_adjusted.ndim > 1 else y_adjusted, sr)
        
        return send_file(tmp_path, mimetype='audio/wav', as_attachment=False)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    print(f"📂 音频目录: {BASE_DIR}")
    print(f"🚫 排除文件夹: {TEMP_EXCLUDE}")
    print("🌐 启动服务: http://localhost:5000")
    print("📄 打开浏览器访问: http://localhost:5000")
    app.run(debug=True, host='0.0.0.0', port=5000)