FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN pip install --no-cache-dir \
	azure-ai-agentserver-agentframework==1.0.0b16 \
	azure-ai-agentserver-core==1.0.0b16

RUN pip install --no-cache-dir \
	agent-framework-core==1.0.0rc6 \
	agent-framework-foundry==1.0.0rc6 \
	agent-framework-openai==1.0.0rc6 \
	python-dotenv==1.0.1 \
	azure-identity==1.25.3

COPY . .

EXPOSE 8088

CMD ["python", "main.py"]
