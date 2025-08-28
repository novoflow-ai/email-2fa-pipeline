const AWS = require('aws-sdk');
const s3 = new AWS.S3();
const dynamodb = new AWS.DynamoDB.DocumentClient();

const DYNAMODB_TABLE = process.env.DYNAMODB_TABLE;
const TENANT_CONFIGS = JSON.parse(process.env.TENANT_CONFIGS || '{}');

exports.handler = async (event) => {
    console.log('=== S3 EVENT PROCESSOR ===');
    console.log('Event:', JSON.stringify(event, null, 2));
    
    const results = [];
    
    // Process each S3 event record
    for (const record of event.Records || []) {
        if (record.eventSource !== 'aws:s3') continue;
        
        const bucket = record.s3.bucket.name;
        const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
        
        console.log(`Processing: ${bucket}/${key}`);
        
        try {
            // Get the email content
            const emailData = await s3.getObject({
                Bucket: bucket,
                Key: key
            }).promise();
            
            const emailContent = emailData.Body.toString('utf-8');
            
            // Extract recipient and sender from email headers
            const toMatch = emailContent.match(/^(?:To|Delivered-To|X-Original-To):\s*(.+)$/mi);
            const fromMatch = emailContent.match(/^From:\s*(.+)$/mi);
            
            let recipient = toMatch ? toMatch[1].trim() : 'unknown';
            let sender = fromMatch ? fromMatch[1].trim() : 'unknown';
            
            // Extract email addresses from "Name <email>" format if present
            if (recipient.includes('<')) {
                const match = recipient.match(/<([^>]+)>/);
                recipient = match ? match[1] : recipient;
            }
            if (sender.includes('<')) {
                const match = sender.match(/<([^>]+)>/);
                sender = match ? match[1] : sender;
            }
            
            // Extract tenant from recipient (e.g., ermi@auth.novoflow.io -> ermi)
            const tenantMatch = recipient.match(/^([^@]+)@/);
            const tenant = tenantMatch ? tenantMatch[1] : 'default';
            
            // Check sender whitelist if configured
            const tenantConfig = TENANT_CONFIGS[tenant] || {};
            const allowlist = tenantConfig.sender_allowlist || ['*'];
            
            if (!allowlist.includes('*')) {
                // Check if sender is allowed
                const senderAllowed = allowlist.some(allowed => {
                    if (allowed === sender) return true; // Exact match
                    if (allowed.startsWith('@') && sender.endsWith(allowed)) return true; // Domain match
                    if (allowed.startsWith('*@') && sender.endsWith(allowed.substring(1))) return true; // Wildcard domain
                    return false;
                });
                
                if (!senderAllowed) {
                    console.warn(`Sender ${sender} not in allowlist for tenant ${tenant}. Skipping.`);
                    results.push({ 
                        recipient, 
                        sender, 
                        status: 'sender_not_allowed',
                        message: `Sender ${sender} not in whitelist` 
                    });
                    continue;
                }
            }
            
            console.log(`Processing email from ${sender} to ${recipient} (tenant: ${tenant})`);
            
            // Extract code using regex
            const codeMatch = emailContent.match(/verification code is:\s*(\d{4,8})/i) ||
                             emailContent.match(/code:\s*(\d{4,8})/i) ||
                             emailContent.match(/\b(\d{6})\b/); // fallback: any 6 digits
            
            if (codeMatch) {
                const code = codeMatch[1];
                console.log(`Found code: ${code}`);
                
                // Store in DynamoDB
                const timestamp = new Date().toISOString();
                await dynamodb.put({
                    TableName: DYNAMODB_TABLE,
                    Item: {
                        pk: `email#${key}`,
                        sk: timestamp,
                        code: code,
                        recipient: recipient,
                        sender: sender,
                        tenant: tenant,
                        status: 'ACTIVE',
                        expiresAt: Math.floor(Date.now() / 1000) + 900, // 15 minutes
                        source: 's3-event',
                        s3Key: key,
                        processedAt: timestamp
                    }
                }).promise();
                
                console.log(`Code stored for ${recipient} from ${sender} (tenant: ${tenant})`);
                results.push({ recipient, sender, code, status: 'success' });
                
                // Publish metrics
                const cloudwatch = new AWS.CloudWatch();
                await cloudwatch.putMetricData({
                    Namespace: '2FA-Parser',
                    MetricData: [{
                        MetricName: 'CodesProcessed',
                        Value: 1,
                        Unit: 'Count',
                        Dimensions: [
                            { Name: 'Environment', Value: process.env.ENVIRONMENT || 'dev' },
                            { Name: 'Tenant', Value: tenant }
                        ]
                    }]
                }).promise();
                
            } else {
                console.warn(`No code found in ${key}`);
                results.push({ key, status: 'no_code_found' });
            }
            
        } catch (err) {
            console.error(`Error processing ${key}:`, err);
            results.push({ key, status: 'error', error: err.message });
        }
    }
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            processed: results.length,
            results: results
        })
    };
};
