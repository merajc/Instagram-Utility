import base64
import concurrent.futures
import io
import json
import os
import sys
import time

import mplcursors
import numpy as np
import psutil
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from matplotlib.offsetbox import AnnotationBbox, OffsetImage
from PIL import Image, ImageDraw, ImageFont, ImageOps
from PyQt5 import QtWidgets
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont
from PyQt5.QtWidgets import (
    QApplication,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QSlider,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

# Portrait images are accepted as 9:16 within this tolerance of the exact ratio.
NINE_SIXTEEN = (0.5623, 0.5627)
FOUR_THIRDS = 4 / 3
ASPECT_TOLERANCE = 0.001

# Pillow resolves bare filenames against the platform font path. Arial is present on
# macOS but usually absent on Linux, so fall back to a font that ships with the OS.
FONT_CANDIDATES = (
    "Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)
_font_warning_shown = False


def load_font(size):
    """Return the first font that actually loads at *size*.

    Falling back silently is what made the old code look like the height slider was
    broken: `load_default()` on Pillow < 10.1 is a fixed-size bitmap font that ignores
    the requested size entirely.
    """
    for candidate in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    try:
        return ImageFont.load_default(size=size)  # Pillow >= 10.1
    except TypeError:
        return ImageFont.load_default()

# Add this function to handle EXIF data extraction
def get_exif_data(image):
    try:
        exif = image._getexif()
        if not exif:
            # Must match the 6-value return below (iso, aperture, ss, camera, lens, focal_length)
            return "N/A", "N/A", "N/A", "N/A", "N/A", "N/A"
        
        # Get basic settings
        iso = exif.get(34855, "N/A")  # ISO
        if aperture := exif.get(37378):
            aperture = f"f/{float(aperture):.1f}"
        else:
            aperture = "N/A"
        
        if ss := exif.get(37377):  # ShutterSpeedValue
            ss_value = 2 ** (-float(ss))  # Convert from APEX to decimal seconds
            if ss_value < 1:
                denominator = round(1/ss_value)  # Round the denominator to nearest integer
                ss = f"1/{denominator}"
            else:
                ss = f"{ss_value:.1f}"
        else:
            ss = "N/A"
        
        # Get focal length
        if focal := exif.get(37386):  # FocalLength
            focal_length = f"{int(float(focal))}mm"
        else:
            focal_length = "N/A"

        # Get camera and lens info
        camera = exif.get(0x0110, "N/A")  # Camera model
        lens = exif.get(0xA434, "N/A")    # Lens model
            
        return iso, aperture, ss, camera, lens, focal_length
    except Exception:
        return "N/A", "N/A", "N/A", "N/A", "N/A", "N/A"

def get_aspect_ratio(width, height):
    return width / height

def expand_image(image):
    width, height = image.size
    aspect_ratio = get_aspect_ratio(width, height)
    target_aspect_ratio = FOUR_THIRDS
    
    if (aspect_ratio > target_aspect_ratio):  # Wider than 4:3, add top and bottom bars
        new_height = int(width / target_aspect_ratio)
        new_width = width
    else:  # Taller than 4:3, add left and right bars
        new_width = int(height * target_aspect_ratio)
        new_height = height
    
    new_image = Image.new("RGB", (new_width, new_height), (255, 255, 255))
    paste_x = (new_width - width) // 2
    paste_y = (new_height - height) // 2
    new_image.paste(image, (paste_x, paste_y))
    return new_image

def process_image(file_path, output_dir, overlay_text, text_height_percent, margin_percent):
    try:
        start_time = time.time()
        filename = os.path.basename(file_path)
        with Image.open(file_path) as opened:
            image_format = opened.format or "JPEG"
            # Rotate to the orientation the photographer actually saw before measuring.
            # Phone cameras store portrait shots landscape plus an orientation tag.
            image = ImageOps.exif_transpose(opened)
            image.load()
        file_size = os.path.getsize(file_path) / (1024 * 1024)  # Size in MB
        
        # Create thumbnail
        thumb = image.copy()
        thumb.thumbnail((100, 100))  # Resize to thumbnail
        buffer = io.BytesIO()
        thumb.save(buffer, format='PNG')
        thumb_data = base64.b64encode(buffer.getvalue()).decode()
        
        width, height = image.size
        aspect_ratio = get_aspect_ratio(width, height)
        
        if NINE_SIXTEEN[0] <= aspect_ratio <= NINE_SIXTEEN[1]:
            # Add text overlay
            draw = ImageDraw.Draw(image)
            font_size = int(height * text_height_percent)
            font = load_font(font_size)
            
            # Get EXIF data
            iso, aperture, ss, camera, lens, focal_length = get_exif_data(image)
            
            # Prepare text
            text1 = overlay_text
            text_camera = f"{camera} + {lens}" if lens != "N/A" else camera
            text2 = f"ISO {iso} | {aperture} | SS {ss} | {focal_length}"
            
            # Position calculation 
            margin_x = int(width * margin_percent)
            margin_y = int(height * margin_percent)
            
            # Add text with black outline for better visibility
            for offset in [(-2,-2), (-2,2), (2,-2), (2,2)]:
                draw.text((margin_x + offset[0], height - margin_y - font_size*3 + offset[1]), text1, font=font, fill='black')
                draw.text((margin_x + offset[0], height - margin_y - font_size*2 + offset[1]), text_camera, font=font, fill='black')
                draw.text((margin_x + offset[0], height - margin_y - font_size + offset[1]), text2, font=font, fill='black')
            
            # Add main white text
            draw.text((margin_x, height - margin_y - font_size*3), text1, font=font, fill='white')
            draw.text((margin_x, height - margin_y - font_size*2), text_camera, font=font, fill='white')
            draw.text((margin_x, height - margin_y - font_size), text2, font=font, fill='white')
            
            output_path = os.path.join(output_dir, filename)
            image.save(output_path, format=image_format, quality=100)
            return "processed", (time.time() - start_time) * 1000, filename, file_size, thumb_data, f"Added overlay: {filename}"
        
        if abs(aspect_ratio - FOUR_THIRDS) < ASPECT_TOLERANCE:
            output_path = os.path.join(output_dir, filename)
            image.save(output_path, format=image_format, quality=100)
            return "skipped", (time.time() - start_time) * 1000, filename, file_size, thumb_data, f"Copied: {filename}"
        
        new_image = expand_image(image)
        output_path = os.path.join(output_dir, filename)
        new_image.save(output_path, format=image_format, quality=100)
        return "processed", (time.time() - start_time) * 1000, filename, file_size, thumb_data, f"Processed: {filename}"
    except Exception as e:
        return "error", 0, os.path.basename(file_path), 0, None, f"Error processing {file_path}: {e}"

class MaterialButton(QPushButton):
    def __init__(self, text, parent=None, primary=True):
        super().__init__(text, parent)
        self.setMinimumHeight(36)
        self.setCursor(Qt.PointingHandCursor)
        
        if primary:
            self.setStyleSheet("""
                QPushButton {
                    background-color: #2196F3;
                    color: white;
                    border: none;
                    border-radius: 4px;
                    padding: 8px 16px;
                    font-size: 14px;
                    font-weight: 500;
                }
                QPushButton:hover {
                    background-color: #1976D2;
                }
                QPushButton:pressed {
                    background-color: #0D47A1;
                }
            """)
        else:
            self.setStyleSheet("""
                QPushButton {
                    background-color: #E0E0E0;
                    color: #424242;
                    border: none;
                    border-radius: 4px;
                    padding: 8px 16px;
                    font-size: 14px;
                    font-weight: 500;
                }
                QPushButton:hover {
                    background-color: #BDBDBD;
                }
                QPushButton:pressed {
                    background-color: #9E9E9E;
                }
            """)

class ImageProcessorApp(QWidget):
    def __init__(self):
        super().__init__()
        self.thumbnails = {}
        self.active_annotations = []
        self.settings_file = os.path.join(os.path.dirname(__file__), 'settings.json')
        self.load_settings()
        self.initUI()
        self.applyTheme()

    def load_settings(self):
        try:
            if os.path.exists(self.settings_file):
                with open(self.settings_file, 'r') as f:
                    settings = json.load(f)
                    self.overlay_text = settings.get('overlay_text', 'Japan Dec 2024')
                    self.text_height_percent = settings.get('text_height', 0.02)
                    self.margin_percent = settings.get('margin', 0.05)
            else:
                self.overlay_text = 'Japan Dec 2024'
                self.text_height_percent = 0.02
                self.margin_percent = 0.05
        except Exception:
            self.overlay_text = 'Japan Dec 2024'
            self.text_height_percent = 0.02
            self.margin_percent = 0.05

    def save_settings(self):
        try:
            with open(self.settings_file, 'w') as f:
                json.dump({
                    'overlay_text': self.overlay_text,
                    'text_height': self.text_height_percent,
                    'margin': self.margin_percent
                }, f)
        except OSError as exc:
            print(f"Could not save settings to {self.settings_file}: {exc}", file=sys.stderr)

    def applyTheme(self):
        # Update container styles
        containers = [
            self.findChild(QWidget, name) 
            for name in ["title_container", "log_container", "chart_container", "stats_container"]
        ]
        for container in containers:
            if container:
                container.setStyleSheet("""
                    QWidget {
                        background-color: white;
                        border-radius: 8px;
                        border: 1px solid #E0E0E0;
                    }
                """)

        self.setStyleSheet("""
            QWidget {
                background-color: #FAFAFA;
                color: #212121;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto;
            }
            QProgressBar {
                border: none;
                border-radius: 4px;
                background-color: #E0E0E0;
                height: 8px;
                text-align: center;
            }
            QProgressBar::chunk {
                background-color: #2196F3;
                border-radius: 4px;
            }
            QTextEdit {
                border: 1px solid #E0E0E0;
                border-radius: 4px;
                padding: 8px;
                background-color: white;
            }
            QLabel {
                color: #424242;
                font-size: 13px;
            }
        """)
        self.directory_label.setStyleSheet("""
            color: #1976D2;
            margin: 16px;
            padding: 8px 16px;
            background: white;
            border: 1px solid #E0E0E0;
            border-radius: 4px;
            min-width: 300px;
        """)

    def initUI(self):
        self.setWindowTitle('Image Processor')
        self.setGeometry(100, 100, 1200, 800)

        main_layout = QHBoxLayout()
        main_layout.setSpacing(16)
        main_layout.setContentsMargins(24, 24, 24, 24)

        # Left layout for charts and controls
        left_layout = QVBoxLayout()
        left_layout.setSpacing(16)

        # Top bar with directory name and select folder button
        top_bar = QHBoxLayout()
        self.directory_label = QLabel('Select a directory to start...', self)
        self.directory_label.setFont(QFont('Roboto', 16))
        self.directory_label.setStyleSheet("color: #BB86FC; margin: 16px;")
        top_bar.addWidget(self.directory_label)

        select_button = MaterialButton('Select Folder', self)
        select_button.clicked.connect(self.select_directory)
        top_bar.addWidget(select_button)
        top_bar.addStretch()

        left_layout.addLayout(top_bar)

        # Add after the select button in the top bar
        self.text_input = QtWidgets.QLineEdit(self.overlay_text, self)
        self.text_input.setPlaceholderText("Enter overlay text")
        self.text_input.textChanged.connect(self.on_text_changed)
        self.text_input.setStyleSheet("""
            QLineEdit {
                padding: 8px;
                border: 1px solid #E0E0E0;
                border-radius: 4px;
                background: white;
                min-width: 200px;
                font-size: 14px;
            }
        """)
        top_bar.addWidget(self.text_input)

        # Progress bar (add this)
        self.progress_bar = QProgressBar(self)
        self.progress_bar.setVisible(False)
        left_layout.addWidget(self.progress_bar)

        # Log section (add this)
        log_container = QWidget()
        log_container.setObjectName("log_container")
        log_layout = QVBoxLayout(log_container)
        
        self.log_text = QTextEdit(self)
        self.log_text.setReadOnly(True)
        self.log_text.setMaximumHeight(100)
        self.log_text.setVisible(False)
        log_layout.addWidget(self.log_text)
        
        left_layout.addWidget(log_container)

        # Chart section
        chart_container = QWidget()
        chart_container.setObjectName("chart_container")
        chart_container.setStyleSheet("""
            QWidget {
                background-color: white;
                border-radius: 8px;
            }
        """)
        chart_layout = QHBoxLayout(chart_container)

        self.figure = Figure(facecolor='#FFFFFF')
        self.canvas = FigureCanvas(self.figure)
        self.canvas.setVisible(False)
        chart_layout.addWidget(self.canvas)

        left_layout.addWidget(chart_container)

        main_layout.addLayout(left_layout)

        # Right sidebar for stats
        right_sidebar = QVBoxLayout()
        right_sidebar.setSpacing(16)

        # Stats container with background
        stats_container = QWidget()
        stats_container.setObjectName("stats_container")
        stats_container.setStyleSheet("""
            QWidget {
                background-color: white;
                border-radius: 8px;
                border: 1px solid #E0E0E0;
                padding: 16px;
            }
            QLabel {
                color: #424242;
                font-size: 14px;
                font-weight: 500;
            }
        """)
        stats_layout = QVBoxLayout(stats_container)

        self.cpu_label = QLabel('CPU Usage: N/A', self)
        self.memory_label = QLabel('Memory Usage: N/A', self)
        self.time_label = QLabel('Time Taken: N/A', self)

        for label in [self.cpu_label, self.memory_label, self.time_label]:
            label.setFont(QFont('Roboto', 14))
            stats_layout.addWidget(label)

        right_sidebar.addWidget(stats_container)
        
        settings_group = QGroupBox("Text Settings")
        settings_layout = QVBoxLayout()
        
        # Text height slider
        text_height_layout = QHBoxLayout()
        self.text_height_label = QLabel(f"Text Height: {self.text_height_percent * 100:.1f}%")
        self.text_height_slider = QSlider(Qt.Horizontal)
        self.text_height_slider.setMinimum(10)  # 1.0%
        self.text_height_slider.setMaximum(50)  # 5.0%
        self.text_height_slider.setValue(int(self.text_height_percent * 1000))     # 2.5% default
        self.text_height_slider.valueChanged.connect(self.update_text_height)
        text_height_layout.addWidget(self.text_height_label)
        text_height_layout.addWidget(self.text_height_slider)
        settings_layout.addLayout(text_height_layout)
        
        # Margin slider
        margin_layout = QHBoxLayout()
        self.margin_label = QLabel(f"Margin: {self.margin_percent * 100:.1f}%")
        self.margin_slider = QSlider(Qt.Horizontal)
        self.margin_slider.setMinimum(10)  # 1.0%
        self.margin_slider.setMaximum(100) # 10.0%
        self.margin_slider.setValue(int(self.margin_percent * 1000))     # 5.0% default
        self.margin_slider.valueChanged.connect(self.update_margin)
        margin_layout.addWidget(self.margin_label)
        margin_layout.addWidget(self.margin_slider)
        settings_layout.addLayout(margin_layout)
        
        settings_group.setLayout(settings_layout)
        right_sidebar.addWidget(settings_group)

        right_sidebar.addStretch()
        main_layout.addLayout(right_sidebar)

        self.setLayout(main_layout)

    def on_text_changed(self, text):
        self.overlay_text = text
        self.save_settings()

    def update_text_height(self, value):
        height_percent = value / 10.0
        self.text_height_label.setText(f"Text Height: {height_percent:.1f}%")
        self.text_height_percent = height_percent / 100.0
        self.save_settings()

    def update_margin(self, value):
        margin_percent = value / 10.0
        self.margin_label.setText(f"Margin: {margin_percent:.1f}%")
        self.margin_percent = margin_percent / 100.0
        self.save_settings()

    def select_directory(self):
        directory = str(QFileDialog.getExistingDirectory(self, "Select Directory"))
        if not directory:
            return
        if not self.confirm_clear_output(directory):
            return
        self.directory_label.setText(os.path.basename(directory))
        self.log_text.setVisible(True)  # Show log when processing starts
        self.process_images(directory)
        self.directory_label.setText("Processing complete")

    def confirm_clear_output(self, directory):
        """Ask before wiping existing files out of <directory>/cropped/."""
        output_dir = os.path.join(directory, "cropped")
        if not os.path.isdir(output_dir):
            return True
        existing = [
            name for name in os.listdir(output_dir)
            if os.path.isfile(os.path.join(output_dir, name))
        ]
        if not existing:
            return True
        answer = QtWidgets.QMessageBox.question(
            self,
            "Clear output folder?",
            f"{len(existing)} file(s) already exist in:\n{output_dir}\n\n"
            "They will be deleted before processing. Continue?",
            QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No,
            QtWidgets.QMessageBox.No,
        )
        return answer == QtWidgets.QMessageBox.Yes

    def update_progress(self, message):
        self.log_text.append(message)
        self.progress_bar.setValue(self.progress_bar.value() + 1)
        QApplication.processEvents()

    def plot_results(self, processed_images, skipped_images, error_images, processing_data):
        self.figure.clear()
        self.active_annotations = []
        
        self.figure.set_facecolor('#FFFFFF')
        self.canvas.setStyleSheet("background-color: #FFFFFF;")
        
        text_color = '#000000'
        grid_color = '#E0E0E0'
        
        # Pie chart
        ax1 = self.figure.add_subplot(121)
        labels = ['Processed', 'Skipped', 'Errors']
        sizes = [processed_images, skipped_images, error_images]
        colors = ['#4CAF50', '#FFC107', '#F44336']
        ax1.pie(sizes, labels=labels, colors=colors, autopct='%1.1f%%', startangle=140)
        ax1.axis('equal')
        
        # Bar chart setup and plotting
        ax2 = self.figure.add_subplot(122)
        times, names, sizes = zip(*processing_data)
        x = range(len(times))
        bars = ax2.bar(x, times, color='#2196F3')
        ax2.set_xlabel('Images')
        ax2.set_ylabel('Processing Time (ms)')
        ax2.set_title('Processing Time per Image')
        ax2.tick_params(axis='x', rotation=45)
        
        # Add tooltips with image preview
        def on_hover(sel):
            # Disable default annotation
            sel.annotation.set_visible(False)
            
            # Clear previous annotations
            for ann in self.active_annotations:
                ann.remove()
            self.active_annotations.clear()
            
            x_pos = int(round(sel.target[0]))
            if 0 <= x_pos < len(names):
                filename = names[x_pos]
                thumb_data = self.thumbnails.get(filename, '')
                if thumb_data:
                    img_data = base64.b64decode(thumb_data)
                    img = Image.open(BytesIO(img_data))
                    img_array = np.asarray(img)
                    
                    # Create image annotation
                    imagebox = OffsetImage(img_array, zoom=0.5)
                    imagebox.image.axes = ax2
                    
                    ab = AnnotationBbox(
                        imagebox,
                        (x_pos, times[x_pos]),
                        xybox=(0, 40),
                        xycoords='data',
                        boxcoords="offset points",
                        pad=0.3,
                        arrowprops=dict(arrowstyle="->"),
                        bboxprops=dict(facecolor='white', edgecolor='gray')
                    )
                    ax2.add_artist(ab)
                    self.active_annotations.append(ab)
                    
                    # Add text annotation
                    text_ann = ax2.annotate(
                        f'File: {filename}\nSize: {sizes[x_pos]:.2f}MB\nTime: {times[x_pos]:.2f}ms',
                        xy=(x_pos, times[x_pos]),
                        xytext=(0, -20),
                        textcoords='offset points',
                        ha='center',
                        va='top',
                        bbox=dict(boxstyle='round,pad=0.5', fc='white', ec='gray')
                    )
                    self.active_annotations.append(text_ann)
                    
                    self.canvas.draw_idle()
        
        cursor = mplcursors.cursor(bars, hover=True)
        cursor.connect("add", on_hover)
        
        # Make sure we have enough room for annotations
        ax2.set_ylim(0, max(times) * 1.4)
        
        # Update text colors
        for ax in [ax1, ax2]:
            ax.tick_params(colors=text_color)
            for text in ax.get_xticklabels() + ax.get_yticklabels():
                text.set_color(text_color)
            ax.xaxis.label.set_color(text_color)
            ax.yaxis.label.set_color(text_color)
            ax.title.set_color(text_color)
        
        self.figure.tight_layout()
        self.canvas.draw()
        self.canvas.setVisible(True)

    def process_images(self, directory):
        output_dir = os.path.join(directory, "cropped")
        os.makedirs(output_dir, exist_ok=True)

        # Clear previous output. Only files — a subdirectory here is someone else's data,
        # and os.remove() on it would raise IsADirectoryError before any work started.
        for entry in os.listdir(output_dir):
            path = os.path.join(output_dir, entry)
            if os.path.isfile(path):
                os.remove(path)
                self.update_progress(f"Deleted {entry} from {output_dir}")
        
        image_files = [os.path.join(directory, f) for f in os.listdir(directory) if f.lower().endswith((".jpg", ".jpeg"))]
        
        if not image_files:
            self.update_progress("No JPEG images found in the directory.")
            self.progress_bar.setVisible(False)
            return
        
        total_images = len(image_files)
        self.progress_bar.setMaximum(total_images)
        self.progress_bar.setVisible(True)
        
        processed_images = 0
        skipped_images = 0
        error_images = 0

        start_time = time.time()
        cpu_usage_start = psutil.cpu_percent(interval=None)
        memory_usage_start = psutil.virtual_memory().percent
        
        processing_data = []  # Will store (time, name, size) tuples
        
        with concurrent.futures.ThreadPoolExecutor() as executor:
            future_to_file = {
                executor.submit(
                    process_image, 
                    file, 
                    output_dir, 
                    self.overlay_text,
                    self.text_height_percent,
                    self.margin_percent
                ): file for file in image_files
            }
            for future in concurrent.futures.as_completed(future_to_file):
                try:
                    result, proc_time, filename, file_size, thumb_data, msg = future.result()
                    if thumb_data:
                        self.thumbnails[filename] = thumb_data
                    self.update_progress(msg)
                    processing_data.append((proc_time, filename, file_size))
                    if result == "processed":
                        processed_images += 1
                    elif result == "skipped":
                        skipped_images += 1
                    else:
                        error_images += 1
                except Exception as e:
                    self.update_progress(f"Error: {e}")
                    error_images += 1
        
        end_time = time.time()
        cpu_usage_end = psutil.cpu_percent(interval=None)
        memory_usage_end = psutil.virtual_memory().percent

        self.update_progress(f"\nProcessing complete. {processed_images} images modified, {skipped_images} copied as-is, {error_images} errors.")
        self.cpu_label.setText(f'CPU Usage: {cpu_usage_start}% -> {cpu_usage_end}%')
        self.memory_label.setText(f'Memory Usage: {memory_usage_start}% -> {memory_usage_end}%')
        self.time_label.setText(f'Time Taken: {end_time - start_time:.2f} seconds')
        self.plot_results(processed_images, skipped_images, error_images, processing_data)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    ex = ImageProcessorApp()
    ex.show()
    sys.exit(app.exec_())
