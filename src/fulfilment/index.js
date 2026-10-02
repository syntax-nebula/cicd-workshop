export const handler = async (event) => {
  console.log('Received OrderPlaced', JSON.stringify(event.detail));
  return { status: 'READY_TO_SHIP' };
};
