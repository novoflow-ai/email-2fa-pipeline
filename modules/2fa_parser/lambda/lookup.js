const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

const DYNAMODB_TABLE = process.env.DYNAMODB_TABLE;

exports.handler = async (event) => {
    console.log('Lookup request:', JSON.stringify(event, null, 2));
    
    try {
        // Parse request body
        const body = JSON.parse(event.body || '{}');
        const { recipient } = body;
        
        // Validate input
        if (!recipient) {
            return {
                statusCode: 400,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    error: 'Missing required parameter: recipient'
                })
            };
        }
        
        // Scan for active codes for this recipient
        const params = {
            TableName: DYNAMODB_TABLE,
            FilterExpression: 'recipient = :recipient AND #status = :status',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':recipient': recipient,
                ':status': 'ACTIVE'
            }
        };
        
        const result = await dynamodb.scan(params).promise();
        console.log(`Found ${result.Items?.length || 0} active codes for ${recipient}`);
        
        if (!result.Items || result.Items.length === 0) {
            return {
                statusCode: 404,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    error: 'No active code found for this recipient'
                })
            };
        }
        
        // Get the most recent code
        const mostRecent = result.Items.sort((a, b) => b.sk.localeCompare(a.sk))[0];
        
        // Mark as used
        await dynamodb.update({
            TableName: DYNAMODB_TABLE,
            Key: {
                pk: mostRecent.pk,
                sk: mostRecent.sk
            },
            UpdateExpression: 'SET #status = :used',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':used': 'USED'
            }
        }).promise();
        
        console.log(`Code retrieved and marked as used for ${recipient}`);
        
        // Return the code
        return {
            statusCode: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                code: mostRecent.code,
                recipient: mostRecent.recipient,
                expiresAt: new Date(mostRecent.expiresAt * 1000).toISOString()
            })
        };
        
    } catch (err) {
        console.error('Lookup error:', err);
        
        return {
            statusCode: 500,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                error: 'Internal server error'
            })
        };
    }
};
