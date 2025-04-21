const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');

async function generateAppIcon() {
  // Configuration
  const sourceImage = path.join(__dirname, 'RedactIQ.png');
  const targetIcon = path.join(__dirname, 'build-resources', 'icon.png');
  const iconSize = 512;
  const backgroundColor = 'rgba(0, 0, 0, 0)'; // Transparent background
  const scaleFactor = 0.9; // Keep the current size
  
  // Create directory if it doesn't exist
  const buildResourcesDir = path.join(__dirname, 'build-resources');
  if (!fs.existsSync(buildResourcesDir)) {
    fs.mkdirSync(buildResourcesDir, { recursive: true });
  }
  
  try {
    // Check if source image exists
    if (!fs.existsSync(sourceImage)) {
      console.error(`Source image not found: ${sourceImage}`);
      process.exit(1);
    }
    
    // Create canvas
    const canvas = createCanvas(iconSize, iconSize);
    const ctx = canvas.getContext('2d');
    
    // Load image first so we can analyze it
    const img = await loadImage(sourceImage);
    
    // Calculate scaling to fit within the scaled canvas
    const maxSize = iconSize * scaleFactor;
    let width = img.width;
    let height = img.height;
    
    if (width > height) {
      if (width > maxSize) {
        height = height * (maxSize / width);
        width = maxSize;
      }
    } else {
      if (height > maxSize) {
        width = width * (maxSize / height);
        height = maxSize;
      }
    }
    
    // Center the image
    const x = (iconSize - width) / 2;
    const y = (iconSize - height) / 2;
    
    // Clear the canvas with transparency
    ctx.clearRect(0, 0, iconSize, iconSize);
    
    // Draw a macOS-style squircle path
    drawMacOSSquircle(ctx, iconSize);
    
    // Fill with transparent background
    ctx.fillStyle = backgroundColor;
    ctx.fill();
    
    // Set this shape as the clipping region
    ctx.clip();
    
    // Draw the image
    ctx.drawImage(img, x, y, width, height);
    
    // Save the icon
    const buffer = canvas.toBuffer('image/png');
    fs.writeFileSync(targetIcon, buffer);
    
    console.log(`App icon generated successfully: ${targetIcon}`);
    return targetIcon;
  } catch (error) {
    console.error('Error generating app icon:', error);
    process.exit(1);
  }
}

// Draw a macOS-style squircle shape
function drawMacOSSquircle(ctx, size) {
  // Constants for the squircle shape
  const radius = size / 2;
  const cornerRadius = radius * 0.45; // Apple's specific corner radius ratio
  
  // Control point distance (approximating Apple's squircle)
  const cpDistance = cornerRadius * 0.55;
  
  // Start drawing
  ctx.beginPath();
  
  // Top edge with corners
  ctx.moveTo(radius - cornerRadius, 0);
  ctx.bezierCurveTo(
    radius - cornerRadius + cpDistance, 0,
    radius, radius - cornerRadius - cpDistance,
    radius, radius - cornerRadius
  );
  ctx.bezierCurveTo(
    radius, radius - cornerRadius + cpDistance,
    radius + cornerRadius - cpDistance, 0,
    radius + cornerRadius, 0
  );
  
  // Right edge with corners
  ctx.lineTo(size, radius - cornerRadius);
  ctx.bezierCurveTo(
    size, radius - cornerRadius + cpDistance,
    size, radius,
    size, radius
  );
  ctx.bezierCurveTo(
    size, radius,
    size, radius + cornerRadius - cpDistance,
    size, radius + cornerRadius
  );
  
  // Bottom edge with corners
  ctx.lineTo(radius + cornerRadius, size);
  ctx.bezierCurveTo(
    radius + cornerRadius - cpDistance, size,
    radius, radius + cornerRadius + cpDistance,
    radius, radius + cornerRadius
  );
  ctx.bezierCurveTo(
    radius, radius + cornerRadius - cpDistance,
    radius - cornerRadius + cpDistance, size,
    radius - cornerRadius, size
  );
  
  // Left edge with corners
  ctx.lineTo(0, radius + cornerRadius);
  ctx.bezierCurveTo(
    0, radius + cornerRadius - cpDistance,
    0, radius,
    0, radius
  );
  ctx.bezierCurveTo(
    0, radius,
    0, radius - cornerRadius + cpDistance,
    0, radius - cornerRadius
  );
  
  // Close the path
  ctx.closePath();
}

// Run the function if this script is executed directly
if (require.main === module) {
  generateAppIcon();
}

module.exports = generateAppIcon; 