// Function to create download links
function createImageDownloadLinks(images, prefix, taskId) {
    const container = document.createElement('div');
    container.style.position = 'fixed';
    container.style.top = '10px';
    container.style.right = '10px';
    container.style.backgroundColor = 'white';
    container.style.padding = '10px';
    container.style.border = '1px solid #ccc';
    container.style.borderRadius = '5px';
    container.style.zIndex = '10000';
    container.style.maxHeight = '80vh';
    container.style.overflowY = 'auto';

    const title = document.createElement('h3');
    title.textContent = 'Download Images';
    title.style.marginBottom = '10px';
    container.appendChild(title);

    images.forEach((url, index) => {
        const link = document.createElement('a');
        link.href = url;
        const filename = images.length === 1 ? 
            `${prefix}_${taskId}.jpg` : 
            `${prefix}${index + 1}_${taskId}.jpg`;
        link.download = filename;
        link.textContent = `Download ${filename}`;
        link.style.display = 'block';
        link.style.marginBottom = '5px';
        link.style.color = 'blue';
        link.style.textDecoration = 'underline';
        link.style.cursor = 'pointer';
        container.appendChild(link);
    });

    const closeButton = document.createElement('button');
    closeButton.textContent = 'Close';
    closeButton.style.marginTop = '10px';
    closeButton.style.padding = '5px 10px';
    closeButton.onclick = () => document.body.removeChild(container);
    container.appendChild(closeButton);

    return container;
}

// Function to trigger download
function triggerDownload(url, filename) {
    return new Promise(resolve => {
        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        console.log(`✅ Downloading: ${filename}`);
        // Add a delay to prevent overwhelming the browser
        setTimeout(resolve, 1000);
    });
}

// Function to download text as a file
function downloadAsFile(content, filename) {
    const blob = new Blob([content], { type: 'text/plain' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    window.URL.revokeObjectURL(url);
}

// Function to get file extension from URL
function getFileExtension(url) {
    return url.split(/[#?]/)[0].split('.').pop().trim().toLowerCase();
}

// Main scraping function
async function scrapeBrainlyTask() {
    try {
        const taskId = window.location.pathname.split('/').pop();
        
        // Get question
        const questionBox = document.querySelector('[data-testid="question_box_text"]');
        const question = questionBox ? questionBox.innerText.trim() : 'Question not found';
        
        // Get question attachments
        let questionAttachments = [];
        const questionAttachmentList = document.querySelector('ul[data-testid="attachments-list-wrapper"]');

        if (questionAttachmentList) {
          // If switcher exists, iterate through thumbnails and scrape high-quality image URLs
          const imageThumbnails = questionAttachmentList.querySelectorAll('li > div');
          for (let i = 0; i < imageThumbnails.length; i++) {
            const thumbnail = imageThumbnails[i];
            thumbnail.click(); // Simulate click to switch to the image

            // Wait for the high-quality image to load
            await new Promise(resolve => setTimeout(resolve, 500));

            // Get the high-quality image
            const highQualityImage = document.querySelector('img.AttachmentsViewerImagePreview-module__image--Oi5AK');
            if (highQualityImage) {
              questionAttachments.push(highQualityImage.src);
            }
          }
        } else {
          // If switcher doesn't exist, scrape the single image URL
          const singleImage = document.querySelector('img.AttachmentsViewerImagePreview-module__image--Oi5AK');
          if (singleImage) {
            questionAttachments.push(singleImage.src);
          }
        }

        // Get answers with their attachments
        const answerBoxes = document.querySelectorAll('[data-testid="answer_box"]');
        const answers = Array.from(answerBoxes).map((answerBox, index) => {
          const answerText = answerBox.querySelector('[data-testid="answer_box_text"]')?.innerText.trim() || '';
          const answerContainer = answerBox.querySelector('.AnswerBoxLayout-module__content---jkD7');
          const attachments = answerContainer
            ? Array.from(answerContainer.querySelectorAll('img'))
                .map(img => img.src)
            : [];
        
          return {
            text: answerText,
            attachments: attachments,
          };
        });

        // Create formatted output
        let formattedText = `URL: ${window.location.href}\n\n`;
        formattedText += `QUESTION:\n${question}\n\n`;
        
        // Handle question attachments
        if (questionAttachments.length > 0) {
            formattedText += 'Question Attachments:\n';
            for (let i = 0; i < questionAttachments.length; i++) {
                const url = questionAttachments[i];
                const filename = questionAttachments.length === 1 ? 
                    `question_${taskId}.jpg` : 
                    `question${i + 1}_${taskId}.jpg`;
                formattedText += `${filename}\n${url}\n`;
            }
            formattedText += '\n';
        }
        
        // Handle answers and their attachments
        for (let i = 0; i < answers.length; i++) {
            const answer = answers[i];
            formattedText += `ANSWER ${i + 1}:\n${answer.text}\n\n`;
            
            if (answer.attachments.length > 0) {
                formattedText += `Answer ${i + 1} Attachments:\n`;
                for (let j = 0; j < answer.attachments.length; j++) {
                    const url = answer.attachments[j];
                    const filename = answer.attachments.length === 1 ? 
                        `answer${i + 1}_${taskId}.jpg` : 
                        `answer${i + 1}.${j + 1}_${taskId}.jpg`;
                    formattedText += `${filename}\n${url}\n`;
                }
                formattedText += '\n';
            }
        }

        // Download the text report
        downloadAsFile(formattedText, `brainly_task_${taskId}.txt`);
        
        // Display in console
        console.log(formattedText);
        console.log(`Found ${questionAttachments.length} question images and ${answers.reduce((sum, a) => sum + a.attachments.length, 0)} answer images`);
        console.log('✅ Scraping completed! Check the downloaded file for content and image URLs.');
        
    } catch (error) {
        console.error('Error scraping Brainly task:', error);
    }
}

// Execute the scraper
scrapeBrainlyTask();
