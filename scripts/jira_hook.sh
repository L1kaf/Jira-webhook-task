#!/bin/bash

. ./.env
#Берем номер задачи с ссылки
ISSUE_KEY=$(echo "$QUERY_STRING" | sed -n 's/.*issue=\$*\([^&]*\).*/\1/p')
echo "$(date) Обрабатывается задача: $ISSUE_KEY" >> $LOG_FILE

# Находим status и родителя через api
STATUS=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY?fields=status" | jq -r '.fields.status.name')
PARENT_KEY=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY?fields=parent" | jq -r '.fields.parent.key')

if [[ "$PARENT_KEY" == "null" ]]; then
  echo "$(date) Задача $ISSUE_KEY не является подзадачей" >> $LOG_FILE
  exit 0
fi

# Логируем для отладки
echo "$(date) Подзадача: $ISSUE_KEY, Статус: $STATUS, Родитель: $PARENT_KEY" >> $LOG_FILE
sleep 1
# Получаем все подзадачи родителя
SUBTASKS=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" "$JIRA_URL/rest/api/2/search?jql=parent=$PARENT_KEY&fields=status")

# Получаем массив статусов
mapfile -t STATUSES < <(echo "$SUBTASKS" | jq -r '.issues[].fields.status.name')

echo "$(date) Статусы подзадач: ${STATUSES[*]}" >> $LOG_FILE

STATUS_ORDER=("Бэклог" "Выбрано для разработки" "В работе" "Код ревью" "Dev тестирование" "Тестирование" "Взято в тестирование" "Готово")

# Функция для получения индекса статуса
get_status_index() {
  local status="$1"
  for i in "${!STATUS_ORDER[@]}"; do
    if [[ "${STATUS_ORDER[$i]}" == "$status" ]]; then
      echo "$i"
      return
    fi
  done
  echo 999  # Если статус не найден
}

# Финальная проверка
ALL_BACKLOG=1
HAS_IN_PROGRESS=0
ALL_SAME_STATUS=1
HAS_SELECTED_FOR_DEV=0
HAS_LATE_STAGE=0
FIRST_STATUS="${STATUSES[0]}"
LOWEST_INDEX=999
LOWEST_STATUS=""


for S in "${STATUSES[@]}"; do
  if [[ "$S" == "В работе" ]]; then
    HAS_IN_PROGRESS=1
  fi
  if [[ "$S" == "Выбрано для разработки" ]]; then
    HAS_SELECTED_FOR_DEV=1
  fi
  if [[ "$S" != "$FIRST_STATUS" ]]; then
    ALL_SAME_STATUS=0
  fi
  if [[ "$S" != "Бэклог" ]]; then
    ALL_BACKLOG=0
  fi

  IDX=$(get_status_index "$S")
  if (( IDX > 1 )); then  # Индексы > 1 — это "Код ревью" и дальше
    HAS_LATE_STAGE=1
  fi
  if (( IDX < LOWEST_INDEX )); then
    LOWEST_INDEX=$IDX
    LOWEST_STATUS="$S"
  fi
done

if [[ "$HAS_IN_PROGRESS" == "1" ]]; then
  TARGET_STATUS="В работе"
elif [[ "$HAS_SELECTED_FOR_DEV" == "1" && "$HAS_IN_PROGRESS" == "0" ]]; then
  TARGET_STATUS="Выбрано для разработки"
elif [[ "$ALL_SAME_STATUS" == "1" ]]; then
  TARGET_STATUS="$FIRST_STATUS"
elif [[ "$ALL_BACKLOG" == "1" ]]; then
  TARGET_STATUS="Бэклог"
elif [[ "$ALL_BACKLOG" == "0" && "$HAS_LATE_STAGE" == "1" && "${STATUSES[*]}" =~ Бэклог ]]; then
  TARGET_STATUS="В работе"
else
  TARGET_STATUS="$LOWEST_STATUS"
fi

# Получаем текущий статус родительской задачи
PARENT_STATUS=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/2/issue/$PARENT_KEY?fields=status" | jq -r '.fields.status.name')

# Сравниваем с целевым статусом
if [[ "$PARENT_STATUS" == "$TARGET_STATUS" ]]; then
  echo "$(date) Статус родителя $PARENT_KEY уже '$PARENT_STATUS' — переход не требуется" >> $LOG_FILE
  exit 0
fi

echo "$(date) Выбран статус '$TARGET_STATUS' для родительской задачи $PARENT_KEY" >> $LOG_FILE

# Получаем доступные переходы для родительской задачи
TRANSITIONS=$(curl -s -H "Authorization: Bearer $JIRA_API_TOKEN" "$JIRA_URL/rest/api/2/issue/$PARENT_KEY/transitions")

# Ищем подходящий transition.id для нужного статуса
TRANSITION_ID=$(echo "$TRANSITIONS" | jq -r --arg STATUS "$TARGET_STATUS" '.transitions[] | select(.to.name == $STATUS) | .id' | head -n 1)

# Проверяем найден ли transition
if [[ -z "$TRANSITION_ID" ]]; then
  echo "$(date) Не найден переход в статус '$TARGET_STATUS' для задачи $PARENT_KEY" >> $LOG_FILE
  echo -e "Status: 200 OK\r"
  echo -e "Content-Type: text/plain\r"
  echo -e "\r"
  echo -e "Webhook received and logged."
  exit 0
fi

# Выполняем переход
curl -s -X POST -H "Authorization: Bearer $JIRA_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"transition\": {\"id\": \"$TRANSITION_ID\"}}" \
     "$JIRA_URL/rest/api/2/issue/$PARENT_KEY/transitions" >> $LOG_FILE

# Успешный лог
echo "$(date) Родительская задача $PARENT_KEY переведена в '$TARGET_STATUS' на основе статусов подзадач."  >> $LOG_FILE


# HTTP-ответ для nginx/fcgiwrap
echo -e "Status: 200 OK\r"
echo -e "Content-Type: text/plain\r"
echo -e "\r"
echo -e "Webhook received and logged."
