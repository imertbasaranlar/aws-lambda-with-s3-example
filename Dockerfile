FROM public.ecr.aws/lambda/nodejs:16

COPY trigger-on-upload.js upload-object.json package*.json ${LAMBDA_TASK_ROOT}/
RUN npm install

CMD [ "trigger-on-upload.handler" ]