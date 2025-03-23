import os
import concurrent.futures
import psutil
import time
import io
import base64
from PyQt5 import QtWidgets, QtCore
from PyQt5.QtWidgets import QFileDialog, QTextEdit, QVBoxLayout, QPushButton, QProgressBar, QLabel, QWidget, QApplication, QHBoxLayout
from PyQt5.QtGui import QFont, QPalette, QColor
from PyQt5.QtCore import Qt
from PyQt5.QtMultimedia import QSound
from matplotlib.figure import Figure
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
import mplcursors  # Changed from mplcursor to mplcursors
from PIL import Image  # Ensure Pillow is installed: pip install Pillow
from matplotlib.offsetbox import AnnotationBbox, OffsetImage
from matplotlib.transforms import Bbox
import matplotlib.pyplot as plt
import numpy as np
from io import BytesIO

def get_aspect_ratio(width, height):
    return width / height

def should_skip_image(width, height):
    aspect_ratio = get_aspect_ratio(width, height)
    return aspect_ratio == 4/3 or (0.5623 <= aspect_ratio <= 0.5627)

def expand_image(image):
    width, height = image.size
    aspect_ratio = get_aspect_ratio(width, height)
    target_aspect_ratio = 4/3
    
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

def process_image(file_path, output_dir, progress_callback, thumbnail_dict):
    try:
        start_time = time.time()
        filename = os.path.basename(file_path)
        image = Image.open(file_path)
        file_size = os.path.getsize(file_path) / (1024 * 1024)  # Size in MB
        
        # Create thumbnail
        thumb = image.copy()
        thumb.thumbnail((100, 100))  # Resize to thumbnail
        buffer = io.BytesIO()
        thumb.save(buffer, format='PNG')
        thumb_data = base64.b64encode(buffer.getvalue()).decode()
        thumbnail_dict[filename] = thumb_data
        
        width, height = image.size
        
        if should_skip_image(width, height):
            output_path = os.path.join(output_dir, filename)
            image.save(output_path, format=image.format, quality=100)
            progress_callback(f"Copied: {filename}")
            return "skipped", (time.time() - start_time) * 1000, filename, file_size
        
        new_image = expand_image(image)
        output_path = os.path.join(output_dir, filename)
        new_image.save(output_path, format=image.format, quality=100)
        progress_callback(f"Processed: {filename}")
        return "processed", (time.time() - start_time) * 1000, filename, file_size
    except Exception as e:
        progress_callback(f"Error processing {file_path}: {e}")
        return "error", 0, filename, 0

class MaterialButton(QPushButton):
    def __init__(self, text, parent=None, primary=True, icon=None):
        super().__init__(text, parent)
        self.setMinimumHeight(36)
        self.setCursor(Qt.PointingHandCursor)
        if icon:
            self.setIcon(icon)
        
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
        self.initUI()
        self.applyTheme()

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
        right_sidebar.addStretch()
        main_layout.addLayout(right_sidebar)

        self.setLayout(main_layout)

    def select_directory(self):
        directory = str(QFileDialog.getExistingDirectory(self, "Select Directory"))
        if directory:
            self.directory_label.setText(os.path.basename(directory))
            self.log_text.setVisible(True)  # Show log when processing starts
            self.process_images(directory)
            self.directory_label.setText("Processing complete")

    def toggleLog(self):
        self.log_visible = not self.log_visible
        self.log_container.setVisible(self.log_visible)

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

        # if there are files inside the output_dir then delete them
        for f in os.listdir(output_dir):
            os.remove(os.path.join(output_dir, f))
            self.update_progress(f"Deleted {f} from {output_dir}")
        
        image_files = [os.path.join(directory, f) for f in os.listdir(directory) if f.lower().endswith((".jpg", ".jpeg"))]
        
        if not image_files:
            self.update_progress("No JPEG images found in the directory.")
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
                    self.update_progress,
                    self.thumbnails
                ): file for file in image_files
            }
            for future in concurrent.futures.as_completed(future_to_file):
                try:
                    result, proc_time, filename, file_size = future.result()
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
        #QSound.play("complete.wav")

if __name__ == "__main__":
    import sys
    app = QApplication(sys.argv)
    ex = ImageProcessorApp()
    ex.show()
    sys.exit(app.exec_())
