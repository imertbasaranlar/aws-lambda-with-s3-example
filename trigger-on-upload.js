console.log('Loading function');
        
const aws = require('aws-sdk');
const fs = require('fs')

const s3 = new aws.S3({ apiVersion: '2006-03-01' });

module.exports.handler = async () => {
    const fileContent = fs.readFileSync('upload-object.json');
    console.log(`file content ${fileContent}`);

    const params = {
        Bucket: 'triggered-lambda-bucket',
        Key: "triggered.json",
        Body: fileContent
    };

    const res = await s3.upload(params).promise();
    console.log("Successfully uploaded ", res);
};
              